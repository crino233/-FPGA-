`timescale 1ns/1ps
module photo_image_scale #(
    parameter integer image_width = 640,
    parameter integer image_height = 480,
    parameter integer min_source_size = 64,
    parameter integer max_source_size = 2048,
    parameter integer max_source_pixels = 2097152,
    parameter integer max_file_bytes = 8388608
) (
    input wire clk, input wire rst_n,
    input wire file_start, input wire [31:0] file_size,
    input wire file_valid, input wire [7:0] file_data,
    input wire [31:0] file_offset, input wire file_end,
    input wire file_cancelled, input wire [7:0] upstream_error,
    output wire file_block,
    input wire pixel_ready,
    output wire pixel_valid, output wire [23:0] pixel_data,
    output reg top_down, output reg frame_commit, output reg stream_end,
    output reg [7:0] error_code,
    output wire [11:0] source_width_out, output wire [11:0] source_height_out
);
    localparam [4:0] st_idle=0, st_header=1, st_validate=2,
        st_multiply=3, st_pixels_check=4, st_extent=5, st_extent_check=6,
        st_crop_height=7, st_crop_size=8, st_crop_origin=9, st_divide=10,
        st_payload=11, st_write_low=12, st_write_high=13,
        st_read_low=14, st_read_low_wait=15, st_read_high=16,
        st_read_high_wait=17, st_send=18, st_failed=19, st_write_check=20;
    localparam integer target_pixels=image_width*image_height;
    localparam integer target_x_bits=$clog2(image_width+1);
    localparam integer target_y_bits=$clog2(image_height+1);
    localparam integer output_count_bits=$clog2(target_pixels+1);
    localparam integer x_rem_bits=$clog2(image_width*2);
    localparam integer y_rem_bits=$clog2(image_height*2);
    localparam integer x_step_bits=$clog2(max_source_size/image_width+1);
    localparam integer y_step_bits=$clog2(max_source_size/image_height+1);
    localparam integer quotient_bits=$clog2(max_source_size/(image_width<image_height ? image_width : image_height)+1);
    reg [4:0] state;
    reg active_flag, end_flag;
    reg [31:0] size_hold;
    reg [23:0] received_bytes, parsed_bytes;
    reg [15:0] signature, planes, bits_per_pixel;
    reg [31:0] declared_size, pixel_offset, dib_size, width_val, height_val, compression;
    reg [11:0] source_width, source_height;
    assign source_width_out=source_width;
    assign source_height_out=source_height;
    wire [31:0] absolute_height=height_val[31] ? -height_val : height_val;
    reg [12:0] row_stride, row_byte;
    reg [11:0] source_x, source_row, completed_source_row;
    reg row_finished;
    reg [21:0] source_pixels, decoded_pixels;
    reg [1:0] color_index;
    reg [7:0] blue_val, green_val;
    reg [23:0] held_pixel, send_pixel;
    reg [11:0] held_x;

    reg [7:0] byte_buffer [0:1023];
    reg [9:0] byte_write_ptr, byte_read_ptr;
    reg [10:0] byte_count;
    reg byte_pending;
    reg [7:0] byte_data;
    wire byte_push=active_flag && file_valid && state!=st_failed && !file_cancelled;
    wire byte_read=active_flag && state!=st_failed && !file_cancelled &&
        (state==st_header || (state==st_payload && !row_finished)) &&
        !byte_pending && byte_count!=0;
    assign file_block=active_flag && state!=st_failed && !file_cancelled && byte_count>504;
    always @(posedge clk) begin
        if(byte_push && byte_count<1024)byte_buffer[byte_write_ptr]<=file_data;
        if(byte_read)byte_data<=byte_buffer[byte_read_ptr];
    end

    reg [23:0] multiply_sum, multiply_addend;
    reg [11:0] multiply_bits;
    reg [3:0] multiply_tick;
    reg multiply_stride;
    wire [23:0] multiply_next=multiply_sum+(multiply_bits[0] ? multiply_addend : 24'd0);
    reg [23:0] payload_size;
    reg [32:0] required_size, header_end;
    reg [11:0] crop_dividend, crop_quotient;
    reg [11:0] crop_width, crop_height, crop_x, crop_y;
    reg [12:0] divide_value;
    reg [quotient_bits-1:0] divide_quotient;
    reg [1:0] divide_kind;
    wire [12:0] divide_limit=divide_kind[1] ? image_height*2 : image_width*2;
    reg [x_step_bits-1:0] x_step, x_initial;
    reg [y_step_bits-1:0] y_step;
    reg [x_rem_bits-1:0] x_step_rem, x_initial_rem, x_remainder;
    reg [y_rem_bits-1:0] y_step_rem, y_remainder;
    reg [11:0] sample_x, sample_y;
    reg [target_x_bits-1:0] target_x, output_x;
    reg [target_y_bits-1:0] target_row;
    reg [output_count_bits-1:0] output_pixels;
    wire [x_rem_bits:0] x_rem_sum={1'b0,x_remainder}+{1'b0,x_step_rem};
    wire x_carry=x_rem_sum>=image_width*2;
    wire [y_rem_bits:0] y_rem_sum={1'b0,y_remainder}+{1'b0,y_step_rem};
    wire y_carry=y_rem_sum>=image_height*2;
    reg x_carry_q,y_carry_q;
    reg [x_rem_bits:0] x_sum_q;
    reg [y_rem_bits:0] y_sum_q;
    reg [11:0] x_base_q,y_base_q,y_next_q;
    reg [y_rem_bits-1:0] y_rem_next;
    wire [11:0] crop_k=crop_quotient<(source_width>>2) ? crop_quotient : (source_width>>2);

    wire row_write=active_flag && !file_cancelled &&
        (state==st_write_low || state==st_write_high);
    wire row_read=active_flag && !file_cancelled &&
        (state==st_read_low || state==st_read_high);
    wire [10:0] row_write_addr=(target_x<<1)+(state==st_write_high);
    wire [15:0] row_write_data=state==st_write_low ? held_pixel[15:0] : {8'd0,held_pixel[23:16]};
    wire [10:0] row_read_addr=(output_x<<1)+(state==st_read_high);
    wire [15:0] row_read_data;
    reg [15:0] row_low;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.IMPLEMENT("32K")
    ) row_buffer (
        .dia(row_write_data),.dib(16'd0),.addra(row_write_addr),.addrb(row_read_addr),
        .cea(row_write),.ceb(row_read),.clka(clk),.clkb(clk),.wea(row_write),.web(1'b0),
        .ocea(1'b1),.oceb(1'b1),.bea(1'b1),.beb(1'b1),
        .rsta(1'b0),.rstb(1'b0),.doa(),.dob(row_read_data));
    assign pixel_valid=active_flag && state==st_send && !file_cancelled;
    assign pixel_data=send_pixel;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=st_idle;active_flag<=0;end_flag<=0;size_hold<=0;
            received_bytes<=0;parsed_bytes<=0;signature<=0;planes<=0;bits_per_pixel<=0;
            declared_size<=0;pixel_offset<=0;dib_size<=0;width_val<=0;height_val<=0;compression<=0;
            source_width<=0;source_height<=0;row_stride<=0;row_byte<=0;
            source_x<=0;source_row<=0;completed_source_row<=0;row_finished<=0;
            source_pixels<=0;decoded_pixels<=0;color_index<=0;blue_val<=0;green_val<=0;
            held_pixel<=0;send_pixel<=0;held_x<=0;
            byte_write_ptr<=0;byte_read_ptr<=0;byte_count<=0;byte_pending<=0;
            multiply_sum<=0;multiply_addend<=0;multiply_bits<=0;multiply_tick<=0;multiply_stride<=0;
            payload_size<=0;required_size<=0;header_end<=0;
            crop_dividend<=0;crop_quotient<=0;crop_width<=0;crop_height<=0;crop_x<=0;crop_y<=0;
            divide_value<=0;divide_quotient<=0;divide_kind<=0;
            x_step<=0;x_step_rem<=0;x_initial<=0;x_initial_rem<=0;y_step<=0;y_step_rem<=0;
            sample_x<=0;sample_y<=0;x_remainder<=0;y_remainder<=0;
            target_x<=0;target_row<=0;output_x<=0;output_pixels<=0;row_low<=0;
            x_carry_q<=0;y_carry_q<=0;x_sum_q<=0;y_sum_q<=0;x_base_q<=0;y_base_q<=0;y_next_q<=0;y_rem_next<=0;
            top_down<=0;frame_commit<=0;stream_end<=0;error_code<=0;
        end else begin
            frame_commit<=0;stream_end<=0;
            byte_pending<=byte_read;
            if(byte_push)begin byte_write_ptr<=byte_write_ptr+1'b1;received_bytes<=received_bytes+1'b1;end
            if(byte_read)byte_read_ptr<=byte_read_ptr+1'b1;
            case({byte_push,byte_read})
                2'b10:byte_count<=byte_count+1'b1;
                2'b01:byte_count<=byte_count-1'b1;
                default:;
            endcase
            if(file_end)end_flag<=1;
            if(file_start)begin
                state<=st_header;active_flag<=1;end_flag<=0;size_hold<=file_size;
                received_bytes<=0;parsed_bytes<=0;signature<=0;planes<=0;bits_per_pixel<=0;
                declared_size<=0;pixel_offset<=0;dib_size<=0;width_val<=0;height_val<=0;compression<=0;
                byte_write_ptr<=0;byte_read_ptr<=0;byte_count<=0;byte_pending<=0;
                source_x<=0;source_row<=0;row_byte<=0;row_finished<=0;
                decoded_pixels<=0;color_index<=0;target_x<=0;target_row<=0;output_pixels<=0;
                top_down<=0;error_code<=0;
            end else if(active_flag)begin
                if(file_cancelled)begin
                    active_flag<=0;state<=st_idle;stream_end<=1;
                    byte_count<=0;byte_pending<=0;
                end else if(state==st_failed)begin
                    byte_count<=0;byte_pending<=0;state<=st_failed;
                    if(end_flag)begin active_flag<=0;state<=st_idle;stream_end<=1;end
                end else begin
                    if(byte_pending)parsed_bytes<=parsed_bytes+1'b1;
                    case(state)
                        st_header:if(byte_pending)begin
                            case(parsed_bytes[5:0])
                                0:signature[7:0]<=byte_data;1:signature[15:8]<=byte_data;
                                2:declared_size[7:0]<=byte_data;3:declared_size[15:8]<=byte_data;
                                4:declared_size[23:16]<=byte_data;5:declared_size[31:24]<=byte_data;
                                10:pixel_offset[7:0]<=byte_data;11:pixel_offset[15:8]<=byte_data;
                                12:pixel_offset[23:16]<=byte_data;13:pixel_offset[31:24]<=byte_data;
                                14:dib_size[7:0]<=byte_data;15:dib_size[15:8]<=byte_data;
                                16:dib_size[23:16]<=byte_data;17:dib_size[31:24]<=byte_data;
                                18:width_val[7:0]<=byte_data;19:width_val[15:8]<=byte_data;
                                20:width_val[23:16]<=byte_data;21:width_val[31:24]<=byte_data;
                                22:height_val[7:0]<=byte_data;23:height_val[15:8]<=byte_data;
                                24:height_val[23:16]<=byte_data;25:height_val[31:24]<=byte_data;
                                26:planes[7:0]<=byte_data;27:planes[15:8]<=byte_data;
                                28:bits_per_pixel[7:0]<=byte_data;29:bits_per_pixel[15:8]<=byte_data;
                                30:compression[7:0]<=byte_data;31:compression[15:8]<=byte_data;
                                32:compression[23:16]<=byte_data;33:compression[31:24]<=byte_data;
                                default:;
                            endcase
                            if(parsed_bytes==53)state<=st_validate;
                        end
                        st_validate:begin
                            if(signature!=16'h4d42)begin error_code<=8'h31;state<=st_failed;end
                            else if(width_val<min_source_size || width_val>max_source_size ||
                                absolute_height<min_source_size || absolute_height>max_source_size || dib_size<40)begin
                                error_code<=8'h32;state<=st_failed;
                            end else if(planes!=1 || bits_per_pixel!=24 || compression!=0)begin
                                error_code<=8'h33;state<=st_failed;
                            end else begin
                                source_width<=width_val[11:0];source_height<=absolute_height[11:0];
                                top_down<=height_val[31];
                                row_stride<=(({1'b0,width_val[11:0]}<<1)+{1'b0,width_val[11:0]}+13'd3)&13'h1ffc;
                                multiply_sum<=0;multiply_addend<={12'd0,width_val[11:0]};
                                multiply_bits<=absolute_height[11:0];multiply_tick<=0;multiply_stride<=0;
                                state<=st_multiply;
                            end
                        end
                        st_multiply:begin
                            multiply_sum<=multiply_next;multiply_addend<=multiply_addend<<1;
                            multiply_bits<=multiply_bits>>1;multiply_tick<=multiply_tick+1'b1;
                            if(multiply_tick==11)begin
                                if(multiply_stride)begin payload_size<=multiply_next;state<=st_extent;end
                                else begin source_pixels<=multiply_next[21:0];state<=st_pixels_check;end
                            end
                        end
                        st_pixels_check:begin
                            if(multiply_sum>max_source_pixels)begin error_code<=8'h32;state<=st_failed;end
                            else begin
                                multiply_sum<=0;multiply_addend<={11'd0,row_stride};
                                multiply_bits<=source_height;multiply_tick<=0;multiply_stride<=1;state<=st_multiply;
                            end
                        end
                        st_extent:begin
                            required_size<={1'b0,pixel_offset}+{9'd0,payload_size};
                            header_end<={1'b0,dib_size}+33'd14;state<=st_extent_check;
                        end
                        st_extent_check:begin
                            if(required_size[32] || {1'b0,pixel_offset}<header_end || size_hold>max_file_bytes)begin
                                error_code<=8'h36;state<=st_failed;
                            end else if(required_size>size_hold || declared_size<required_size || declared_size>size_hold)begin
                                error_code<=8'h37;state<=st_failed;
                            end else begin crop_dividend<=source_height;crop_quotient<=0;state<=st_crop_height;end
                        end
                        st_crop_height:begin
                            if(crop_dividend>=3)begin crop_dividend<=crop_dividend-12'd3;crop_quotient<=crop_quotient+1'b1;end
                            else state<=st_crop_size;
                        end
                        st_crop_size:begin crop_width<=crop_k<<2;crop_height<=(crop_k<<1)+crop_k;state<=st_crop_origin;end
                        st_crop_origin:begin
                            crop_x<=(source_width-crop_width)>>1;
                            crop_y<=(source_height-crop_height+!top_down)>>1;
                            divide_value<={crop_width,1'b0};divide_quotient<=0;divide_kind<=0;state<=st_divide;
                        end
                        st_divide:begin
                            if(divide_value>=divide_limit)begin
                                divide_value<=divide_value-divide_limit;divide_quotient<=divide_quotient+1'b1;
                            end else begin
                                divide_quotient<=0;
                                case(divide_kind)
                                    0:begin x_step<=divide_quotient;x_step_rem<=divide_value[x_rem_bits-1:0];
                                        divide_value<={1'b0,crop_width};divide_kind<=1;end
                                    1:begin x_initial<=divide_quotient;x_initial_rem<=divide_value[x_rem_bits-1:0];
                                        sample_x<=crop_x+divide_quotient;x_remainder<=divide_value[x_rem_bits-1:0];
                                        divide_value<={crop_height,1'b0};divide_kind<=2;end
                                    2:begin y_step<=divide_quotient;y_step_rem<=divide_value[y_rem_bits-1:0];
                                        divide_value<={1'b0,crop_height}-!top_down;divide_kind<=3;end
                                    default:begin sample_y<=crop_y+divide_quotient;y_remainder<=divide_value[y_rem_bits-1:0];state<=st_payload;end
                                endcase
                            end
                        end
                        st_payload:begin
                            if(row_finished)begin
                                row_finished<=0;
                                if(completed_source_row==sample_y && target_row<image_height)begin
                                    if(target_x!=image_width)begin error_code<=8'h37;state<=st_failed;end
                                    else begin output_x<=0;state<=st_read_low;end
                                end
                            end else if(byte_pending && parsed_bytes>=pixel_offset && source_row<source_height)begin
                                if(row_byte<({1'b0,source_width}<<1)+{1'b0,source_width})begin
                                    case(color_index)
                                        0:begin blue_val<=byte_data;color_index<=1;end
                                        1:begin green_val<=byte_data;color_index<=2;end
                                        default:begin
                                            decoded_pixels<=decoded_pixels+1'b1;color_index<=0;source_x<=source_x+1'b1;
                                            if(source_row==sample_y && source_x==sample_x && target_row<image_height && target_x<image_width)begin
                                                held_pixel<={byte_data,green_val,blue_val};held_x<=source_x;state<=st_write_low;
                                            end
                                        end
                                    endcase
                                end
                                if(row_byte==row_stride-1'b1)begin
                                    row_byte<=0;source_x<=0;source_row<=source_row+1'b1;color_index<=0;
                                    row_finished<=1;completed_source_row<=source_row;
                                end else row_byte<=row_byte+1'b1;
                            end
                            if(end_flag && byte_count==0 && !byte_pending && !row_finished)begin
                                active_flag<=0;state<=st_idle;stream_end<=1;
                                if(parsed_bytes==size_hold && received_bytes==size_hold && decoded_pixels==source_pixels &&
                                    source_row==source_height && target_row==image_height && output_pixels==target_pixels)
                                    frame_commit<=1;
                                else error_code<=8'h37;
                            end
                        end
                        st_write_low:begin
                            x_sum_q<=x_rem_sum;x_carry_q<=x_carry;x_base_q<={1'b0,sample_x}+{1'b0,x_step};
                            state<=st_write_high;
                        end
                        st_write_high:begin
                            target_x<=target_x+1'b1;sample_x<=x_base_q+x_carry_q;
                            x_remainder<=x_carry_q ? x_sum_q-image_width*2 : x_sum_q[x_rem_bits-1:0];
                            state<=st_write_check;
                        end
                        st_write_check:begin
                            if(target_x==image_width || sample_x!=held_x)state<=st_payload;
                            else state<=st_write_low;
                        end
                        st_read_low:begin
                            y_sum_q<=y_rem_sum;y_carry_q<=y_carry;y_base_q<={1'b0,sample_y}+{1'b0,y_step};
                            state<=st_read_low_wait;
                        end
                        st_read_low_wait:begin
                            row_low<=row_read_data;y_next_q<=y_base_q+y_carry_q;
                            y_rem_next<=y_carry_q ? y_sum_q-image_height*2 : y_sum_q[y_rem_bits-1:0];state<=st_read_high;
                        end
                        st_read_high:state<=st_read_high_wait;
                        st_read_high_wait:begin send_pixel<={row_read_data[7:0],row_low};state<=st_send;end
                        st_send:if(pixel_ready)begin
                            output_pixels<=output_pixels+1'b1;
                            if(output_x==image_width-1)begin
                                target_row<=target_row+1'b1;output_x<=0;
                                sample_y<=y_next_q;y_remainder<=y_rem_next;
                                if(target_row!=image_height-1 && y_next_q==completed_source_row)state<=st_read_low;
                                else begin
                                    target_x<=0;sample_x<=crop_x+x_initial;x_remainder<=x_initial_rem;state<=st_payload;
                                end
                            end else begin output_x<=output_x+1'b1;state<=st_read_low;end
                        end
                        default:begin error_code<=8'h3f;state<=st_failed;end
                    endcase
                    if(end_flag && state==st_header && byte_count==0 && !byte_pending)begin
                        error_code<=8'h37;state<=st_failed;
                    end
                    if(upstream_error!=0)begin
                        error_code<=8'h38;state<=st_failed;frame_commit<=0;
                    end else if(file_valid && (file_offset!=received_bytes || received_bytes>=size_hold))begin
                        error_code<=8'h39;state<=st_failed;frame_commit<=0;
                    end else if(byte_push && byte_count==1024)begin
                        error_code<=8'h3a;state<=st_failed;frame_commit<=0;
                    end
                end
            end
        end
    end
endmodule
