module photo_wav_stream (
    input wire clk, input wire rst_n, input wire play_enable,
    input wire catalog_ready, input wire fs_busy, input wire fs_done,
    input wire [7:0] fs_error, input wire available,
    output reg file_request, output wire file_pause, output reg load_done,
    output wire [7:0] load_error,
    input wire file_start, input wire [31:0] file_size,
    input wire file_valid, input wire [7:0] file_data,
    input wire [31:0] file_offset, input wire file_end,
    input wire pix_clk, input wire pix_rst_n, input wire consume,
    output wire signed [15:0] sample_data, output wire sample_ready,
    output wire urgent, output reg [7:0] error_code,
    output reg [31:0] samples_written, output reg [31:0] underflows
);
    reg [12:0] write_ptr,read_ptr,write_gray,read_gray;
    (* async_reg="true" *) reg [12:0] read_meta,read_sync,write_meta,write_sync;
    function [12:0] from_gray;
        input [12:0] value;integer i;
        begin from_gray[12]=value[12];for(i=11;i>=0;i=i-1)from_gray[i]=from_gray[i+1]^value[i];end
    endfunction
    wire [12:0] used_write=write_ptr-from_gray(read_sync);
    wire [12:0] used_read=from_gray(write_sync)-read_ptr;
    assign urgent=used_write<2048;
    assign file_pause=!play_enable || used_write>13'd3840;
    reg primed;
    (* async_reg="true" *) reg [1:0] error_sync;
    assign sample_ready=primed && used_read!=0 && !error_sync[1];
    wire [15:0] ram_data;
    reg [7:0] low_byte;
    reg low_pending;
    reg [2:0] parse_state;
    reg [31:0] payload_left;
    wire sample_write=file_valid && parse_state==4 && payload_left!=0 && low_pending && error_code==0;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(12),.ADDR_WIDTH_B(12),
        .DATA_DEPTH_A(4096),.DATA_DEPTH_B(4096),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K"),.INIT_FILE("NONE")) ring_proc(
        .clka(clk),.cea(sample_write),.ocea(1'b1),.wea(sample_write),.rsta(1'b0),.bea(1'b1),
        .addra(write_ptr[11:0]),.dia({file_data,low_byte}),.doa(),
        .clkb(pix_clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.rstb(1'b0),.beb(1'b1),
        .addrb(read_ptr[11:0]),.dib(16'd0),.dob(ram_data));
    assign sample_data=sample_ready ? ram_data : 16'd0;
    reg [31:0] riff_size,chunk_id,chunk_size,chunk_left,file_limit,chunk_remaining;
    reg chunk_low_gt,chunk_low_eq,range_error;
    reg missing_error,storage_error,format_error,header_error,buffer_error;
    reg [3:0] header_index;
    reg [31:0] byte_rate,sample_rate;
    reg [15:0] format_tag,channels,block_align,bits_per_sample;
    reg fmt_ok,request_sent,check_fmt,end_pending;
    wire [31:0] chunk_length={file_data,chunk_size[23:0]};
    assign load_error=error_code;
    always @(posedge pix_clk or negedge pix_rst_n)begin
        if(!pix_rst_n)begin read_ptr<=0;read_gray<=0;write_meta<=0;write_sync<=0;primed<=0;underflows<=0;error_sync<=0;end
        else begin
            write_meta<=write_gray;write_sync<=write_meta;
            error_sync<={error_sync[0],error_code!=0};
            if(used_read>=1024)primed<=1;
            if(consume)begin
                if(sample_ready)begin read_ptr<=read_ptr+1'b1;read_gray<=(read_ptr+13'd1)^((read_ptr+13'd1)>>1);end
                else begin primed<=0;underflows<=underflows+1'b1;end
            end
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            write_ptr<=0;write_gray<=0;read_meta<=0;read_sync<=0;low_byte<=0;low_pending<=0;
            parse_state<=0;riff_size<=0;chunk_id<=0;chunk_size<=0;chunk_left<=0;payload_left<=0;
            file_limit<=0;chunk_remaining<=0;chunk_low_gt<=0;chunk_low_eq<=0;range_error<=0;
            header_index<=0;byte_rate<=0;sample_rate<=0;format_tag<=0;channels<=0;
            block_align<=0;bits_per_sample<=0;fmt_ok<=0;request_sent<=0;check_fmt<=0;end_pending<=0;
            file_request<=0;load_done<=0;error_code<=0;samples_written<=0;
            missing_error<=0;storage_error<=0;format_error<=0;header_error<=0;buffer_error<=0;
        end else begin
            read_meta<=read_gray;read_sync<=read_meta;file_request<=0;load_done<=0;
            if(error_code==0)begin
                if(missing_error)error_code<=8'h90;
                else if(storage_error)error_code<=8'h93;
                else if(format_error)error_code<=8'h92;
                else if(header_error)error_code<=8'h91;
                else if(buffer_error)error_code<=8'h94;
            end
            if(catalog_ready && !fs_busy && !fs_done && !request_sent && play_enable && error_code==0 &&
                !missing_error && !storage_error && !format_error && !header_error && !buffer_error)begin
                if(available)begin file_request<=1;request_sent<=1;end
                else missing_error<=1;
            end
            if(fs_done)begin request_sent<=0;if(fs_error!=0)storage_error<=1;end
            if(file_start)begin
                parse_state<=0;header_index<=0;fmt_ok<=0;riff_size<=0;chunk_size<=0;low_pending<=0;
                payload_left<=0;check_fmt<=0;file_limit<=file_size-8;range_error<=0;
            end
            if(range_error)header_error<=1;
            if(check_fmt)begin
                check_fmt<=0;
                if(format_tag!=1 || channels!=1 || sample_rate!=48000 || byte_rate!=96000 ||
                    block_align!=2 || bits_per_sample!=16)format_error<=1;
                else fmt_ok<=1;
            end
            if(sample_write)begin
                write_ptr<=write_ptr+1'b1;write_gray<=(write_ptr+13'd1)^((write_ptr+13'd1)>>1);
                samples_written<=samples_written+1'b1;
                if(used_write>=4096)buffer_error<=1;
            end
            if(file_valid && error_code==0)begin
                case(parse_state)
                    0:begin
                        header_index<=header_index+1'b1;
                        case(header_index)
                            0:if(file_data!="R")header_error<=1;
                            1:if(file_data!="I")header_error<=1;
                            2,3:if(file_data!="F")header_error<=1;
                            4,5,6,7:riff_size[(header_index-4)*8+:8]<=file_data;
                            8:if(file_data!="W")header_error<=1;
                            9:if(file_data!="A")header_error<=1;
                            10:if(file_data!="V")header_error<=1;
                            11:begin
                                if(file_data!="E" || riff_size<36)header_error<=1;
                                range_error<=riff_size>file_limit;header_index<=0;parse_state<=1;
                            end
                        endcase
                    end
                    1:begin
                        header_index<=header_index+1'b1;
                        if(header_index==0)chunk_remaining<=riff_size-file_offset;
                        if(header_index==6)begin
                            chunk_low_gt<={file_data,chunk_size[15:0]}>chunk_remaining[23:0];
                            chunk_low_eq<={file_data,chunk_size[15:0]}==chunk_remaining[23:0];
                        end
                        if(header_index<4)chunk_id[header_index*8+:8]<=file_data;
                        else chunk_size[(header_index-4)*8+:8]<=file_data;
                        if(header_index==7)begin
                            header_index<=0;chunk_left<=chunk_length;
                            range_error<=file_data>chunk_remaining[31:24] ||
                                (file_data==chunk_remaining[31:24] && (chunk_low_gt || (chunk_low_eq && chunk_size[0])));
                            if(chunk_id==32'h20746d66)begin
                                if(chunk_length<16 || fmt_ok || chunk_length[0])format_error<=1;
                                parse_state<=2;
                            end else if(chunk_id==32'h61746164)begin
                                if(!fmt_ok || chunk_length==0 || chunk_length[0])format_error<=1;
                                payload_left<=chunk_length;parse_state<=4;
                            end else begin
                                chunk_left<=chunk_length+{31'd0,chunk_length[0]};
                                parse_state<=chunk_length==0 ? 1 : 3;
                            end
                        end
                    end
                    2:begin
                        chunk_left<=chunk_left-1'b1;
                        if(header_index<15)header_index<=header_index+1'b1;
                        case(header_index)
                            0,1:format_tag[header_index*8+:8]<=file_data;
                            2,3:channels[(header_index-2)*8+:8]<=file_data;
                            4,5,6,7:sample_rate[(header_index-4)*8+:8]<=file_data;
                            8,9,10,11:byte_rate[(header_index-8)*8+:8]<=file_data;
                            12,13:block_align[(header_index-12)*8+:8]<=file_data;
                            14,15:bits_per_sample[(header_index-14)*8+:8]<=file_data;
                        endcase
                        if(header_index==15)begin check_fmt<=1;parse_state<=chunk_left==1 ? 1 : 3;header_index<=0;end
                    end
                    3:begin chunk_left<=chunk_left-1'b1;if(chunk_left==1)begin parse_state<=1;header_index<=0;end end
                    4:if(payload_left!=0)begin
                        payload_left<=payload_left-1'b1;low_pending<=!low_pending;
                        if(!low_pending)low_byte<=file_data;
                        if(payload_left==1)parse_state<=6;
                    end
                    6:;
                    default:header_error<=1;
                endcase
            end
            end_pending<=file_end;
            if(end_pending)begin
                load_done<=1;
                if(parse_state!=6 || low_pending)header_error<=1;
            end
        end
    end
endmodule
