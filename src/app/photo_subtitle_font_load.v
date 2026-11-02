`timescale 1ns/1ps
module photo_subtitle_font_load (
    input wire clk,rst_n,enable,
    input wire [4:0] notice_length,teacher_length,
    input wire pin_valid,restart,input wire [6:0] pin_index,
    output wire file_request,output wire [31:0] range_offset,output wire file_close,
    input wire file_start,file_valid,file_end,file_finished,file_cancelled,
    input wire [31:0] file_size,file_offset,input wire [7:0] file_data,file_error,
    output reg done,retry,output reg [7:0] error_code,
    output reg mem_en,mem_write_en,output reg [10:0] mem_addr,
    output reg [15:0] mem_write_data,input wire [15:0] mem_read_data
);
    localparam [5:0] st_idle=0,st_scan_map=1,st_scan_wait=2,st_scan_text=3,st_text_wait=4,
        st_scan_next=5,st_select=6,st_request=7,st_receive=8,st_wait=9,
        st_crc_read=10,st_crc_wait=11,st_crc_bit=12,st_crc_finish=13,st_free=14,
        st_desc_code=15,st_desc_slot=16,st_desc_id=17,st_map_read=18,st_map_wait=19,
        st_map_text=20,st_map_text_wait=21,st_map_write=22,st_map_next=23,
        st_glyph_code=24,st_glyph_code_wait=25,st_glyph_slot=26,st_glyph_slot_wait=27,
        st_glyph_id=28,st_glyph_id_wait=29,st_need_block=30,st_clear_tag=31,
        st_row_read=32,st_row_wait=33,st_row_write=34,st_tag_write=35,
        st_glyph_next=36,st_close=37,st_finish=38,st_retry=39,st_index_target=40,st_glyph_target=41;
    reg [41:0] state;
    reg [5:0] cell_index,descriptor_count,descriptor_index;
    reg [15:0] current_code,glyph_id,previous_id,font_count;
    reg minimum_found,header_valid,session_open,cache_valid;
    reg [10:0] target_sector,cache_sector;
    reg [79:0] occupied_slots;
    reg [6:0] cache_slot;
    reg [7:0] byte_high;
    reg [1:0] crc_kind;
    reg [7:0] crc_base,crc_index,crc_last;
    reg [15:0] crc,crc_word,row_value;
    reg [3:0] crc_bit,row_index;
    reg record_bad;
    reg [9:0] received_bytes;
    reg stream_bad;
    wire last_cell=cell_index[5] ? cell_index[4:0]+5'd1==teacher_length :
        teacher_length==0 && cell_index[4:0]+5'd1==notice_length;
    wire [5:0] next_cell=!cell_index[5] && cell_index[4:0]+5'd1==notice_length ? 6'd32 : cell_index+6'd1;
    wire [5:0] first_cell=notice_length!=0 ? 6'd0 : 6'd32;
    wire descriptor_append=state[st_desc_code] || state[st_desc_slot] || state[st_desc_id];
    wire [5:0] descriptor_select=descriptor_append ? descriptor_count : descriptor_index;
    wire [7:0] descriptor_pos={descriptor_select,1'b0}+descriptor_select;
    wire [7:0] descriptor_next=descriptor_pos+8'd1,descriptor_last=descriptor_pos+8'd2;
    wire [7:0] crc_address=crc_base[7:0]+crc_index[7:0]-(crc_kind==1 ? 8'd1 : 8'd0);
    wire [7:0] row_address=crc_base[7:0]+{4'd0,row_index}+8'd1;
    wire [15:0] crc_next=(crc[15]^crc_word[15]) ? {crc[14:0],1'b0}^16'h1021 : {crc[14:0],1'b0};
    wire slot_reserve=enable ? state[st_free] && !occupied_slots[cache_slot] : pin_valid;
    wire [6:0] slot_write_index=enable ? cache_slot : pin_index;
    assign file_request=state[st_request];
    assign file_close=state[st_close];
    assign range_offset={12'd0,target_sector,9'd0};
    task fail_proc;
        input [7:0] code;
        begin error_code<=code;state<=session_open ? 42'd1<<st_close : 42'd1<<st_finish;end
    endtask
    always @* begin
        mem_en=0;mem_write_en=0;mem_addr=0;mem_write_data=0;
        (* parallel_case *) case(1'b1)
            state[st_scan_map],state[st_map_read]:begin mem_en=1;mem_addr=11'd1472+{5'd0,cell_index};end
            state[st_scan_text],state[st_map_text]:begin mem_en=1;mem_addr=11'd1408+{5'd0,cell_index};end
            state[st_desc_code]:begin mem_en=1;mem_write_en=1;mem_addr={3'd7,descriptor_pos};mem_write_data=current_code;end
            state[st_desc_slot]:begin mem_en=1;mem_write_en=1;mem_addr={3'd7,descriptor_next};mem_write_data={9'd0,cache_slot};end
            state[st_desc_id]:begin mem_en=1;mem_write_en=1;mem_addr={3'd7,descriptor_last};mem_write_data=glyph_id;end
            state[st_map_write]:begin mem_en=1;mem_write_en=1;mem_addr=11'd1472+{5'd0,cell_index};mem_write_data={9'd0,cache_slot};end
            state[st_glyph_code]:begin mem_en=1;mem_addr={3'd7,descriptor_pos};end
            state[st_glyph_slot]:begin mem_en=1;mem_addr={3'd7,descriptor_next};end
            state[st_glyph_id]:begin mem_en=1;mem_addr={3'd7,descriptor_last};end
            state[st_crc_read]:begin
                mem_en=!(crc_kind==1 && crc_index==0);
                mem_addr={3'd6,crc_address};
            end
            state[st_clear_tag]:begin mem_en=1;mem_write_en=1;mem_addr=11'd1280+{4'd0,cache_slot};end
            state[st_row_read]:begin mem_en=1;mem_addr={3'd6,row_address};end
            state[st_row_write]:begin mem_en=1;mem_write_en=1;mem_addr={cache_slot,row_index};mem_write_data=row_value;end
            state[st_tag_write]:begin mem_en=1;mem_write_en=1;mem_addr=11'd1280+{4'd0,cache_slot};mem_write_data=current_code;end
        endcase
        if(state[st_receive] && file_valid && file_offset[0])begin
            mem_en=1;mem_write_en=1;mem_addr=11'd1536+{3'd0,file_offset[8:1]};
            mem_write_data={byte_high,file_data};
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=42'd1<<st_idle;done<=0;retry<=0;error_code<=0;cell_index<=0;
            descriptor_count<=0;descriptor_index<=0;current_code<=16'hffff;
            glyph_id<=0;previous_id<=0;font_count<=0;minimum_found<=0;header_valid<=0;
            session_open<=0;cache_valid<=0;target_sector<=0;cache_sector<=0;occupied_slots<=0;
            cache_slot<=0;byte_high<=0;crc_kind<=0;crc_base<=0;crc_index<=0;crc_last<=0;
            crc<=16'hffff;crc_word<=0;crc_bit<=0;row_index<=0;row_value<=0;record_bad<=0;
            received_bytes<=0;stream_bad<=0;
        end else begin
            done<=0;retry<=0;
            if(file_valid && !file_offset[0])byte_high<=file_data;
            (* parallel_case *) case(1'b1)
                state[st_idle]:if(enable)begin
                    descriptor_count<=0;descriptor_index<=0;
                    minimum_found<=0;current_code<=16'hffff;cell_index<=first_cell;
                    header_valid<=0;cache_valid<=0;session_open<=0;error_code<=0;state<=42'd1<<st_scan_map;
                end
                state[st_scan_map]:state<=42'd1<<st_scan_wait;
                state[st_scan_wait]:state<=mem_read_data==16'hffff ? 42'd1<<st_scan_text : 42'd1<<st_scan_next;
                state[st_scan_text]:state<=42'd1<<st_text_wait;
                state[st_text_wait]:begin
                    if(!minimum_found || mem_read_data<current_code)begin minimum_found<=1;current_code<=mem_read_data;end
                    state<=42'd1<<st_scan_next;
                end
                state[st_scan_next]:if(last_cell)state<=42'd1<<st_select;
                    else begin cell_index<=next_cell;state<=42'd1<<st_scan_map;end
                state[st_select]:begin
                    if(!minimum_found)begin descriptor_index<=0;state<=42'd1<<st_glyph_code;end
                    else if(!header_valid)begin
                        target_sector<=0;crc_kind<=0;crc_base<=0;crc_last<=255;state<=42'd1<<st_need_block;
                    end else state<=42'd1<<st_index_target;
                end
                state[st_index_target]:begin
                    target_sector<=11'd1+{2'd0,current_code[15:7]};
                    crc_kind<=1;crc_base<={1'b0,current_code[6:0],1'b0};crc_last<=2;state<=42'd1<<st_need_block;
                end
                state[st_need_block]:begin
                    if(cache_valid && cache_sector==target_sector)begin
                        crc<=16'hffff;crc_index<=0;record_bad<=0;state<=42'd1<<st_crc_read;
                    end else state<=42'd1<<st_request;
                end
                state[st_request]:if(file_start)begin
                    session_open<=1;received_bytes<=0;stream_bad<=0;state<=file_end ? 42'd1<<st_wait : 42'd1<<st_receive;
                end
                state[st_receive]:begin
                    if(file_valid)begin
                        received_bytes<=received_bytes+1'b1;
                        if(file_offset!={12'd0,target_sector,9'd0}+received_bytes || received_bytes>=512)stream_bad<=1;
                    end
                    if(file_end)state<=42'd1<<st_wait;
                end
                state[st_wait]:if(file_finished)begin
                    if(file_error!=0)begin error_code<=file_error;session_open<=0;state<=42'd1<<st_finish;end
                    else if(stream_bad || received_bytes==0 ||
                        (received_bytes!=512 && {12'd0,target_sector,9'd0}+received_bytes!=file_size))fail_proc(8'h85);
                    else begin
                        cache_valid<=1;cache_sector<=target_sector;crc<=16'hffff;crc_index<=0;record_bad<=0;state<=42'd1<<st_crc_read;
                    end
                end
                state[st_crc_read]:state<=42'd1<<st_crc_wait;
                state[st_crc_wait]:begin
                    crc_word<=crc_kind==1 && crc_index==0 ? current_code : mem_read_data;
                    crc_bit<=0;state<=42'd1<<st_crc_bit;
                    if(crc_kind==0)begin
                        case(crc_index)
                            0:if(mem_read_data!=16'h4631)record_bad<=1;
                            1:if(mem_read_data!=16'h3655)record_bad<=1;
                            2:if(mem_read_data!=16'h0210)record_bad<=1;
                            3:if(mem_read_data!=16'h1040)record_bad<=1;
                            4:font_count<=mem_read_data;
                            255:;
                            default:if(mem_read_data!=0)record_bad<=1;
                        endcase
                    end else if(crc_kind==1 && crc_index==1)glyph_id<=mem_read_data;
                    else if(crc_kind==2)begin
                        if(crc_index==0 && mem_read_data!=current_code)record_bad<=1;
                        if(crc_index>=17 && crc_index<31 && mem_read_data!=0)record_bad<=1;
                    end
                end
                state[st_crc_bit]:begin
                    crc<=crc_next;crc_word<={crc_word[14:0],1'b0};crc_bit<=crc_bit+1'b1;
                    if(crc_bit==15)begin
                        if(crc_index==crc_last)state<=42'd1<<st_crc_finish;
                        else begin crc_index<=crc_index+1'b1;state<=42'd1<<st_crc_read;end
                    end
                end
                state[st_crc_finish]:begin
                    if(crc!=0 || record_bad)fail_proc(crc_kind==2 ? 8'h86 : 8'h85);
                    else case(crc_kind)
                        0:if(font_count==0 || font_count>8192 || file_size!=32'd262656+{10'd0,font_count,6'd0})fail_proc(8'h85);
                            else begin header_valid<=1;state<=42'd1<<st_index_target;end
                        1:if(glyph_id==16'hffff)fail_proc(8'h87);
                            else if(glyph_id>=font_count || (descriptor_count!=0 && glyph_id<=previous_id))fail_proc(8'h85);
                            else begin previous_id<=glyph_id;cache_slot<=0;state<=42'd1<<st_free;end
                        default:begin row_index<=0;state<=42'd1<<st_clear_tag;end
                    endcase
                end
                state[st_free]:if(!occupied_slots[cache_slot])begin
                    state<=42'd1<<st_desc_code;
                end else if(cache_slot==79)fail_proc(8'h88);else cache_slot<=cache_slot+1'b1;
                state[st_desc_code]:state<=42'd1<<st_desc_slot;
                state[st_desc_slot]:state<=42'd1<<st_desc_id;
                state[st_desc_id]:begin descriptor_count<=descriptor_count+1'b1;cell_index<=first_cell;state<=42'd1<<st_map_read;end
                state[st_map_read]:state<=42'd1<<st_map_wait;
                state[st_map_wait]:state<=mem_read_data==16'hffff ? 42'd1<<st_map_text : 42'd1<<st_map_next;
                state[st_map_text]:state<=42'd1<<st_map_text_wait;
                state[st_map_text_wait]:state<=mem_read_data==current_code ? 42'd1<<st_map_write : 42'd1<<st_map_next;
                state[st_map_write]:state<=42'd1<<st_map_next;
                state[st_map_next]:if(last_cell)begin
                    cell_index<=first_cell;minimum_found<=0;current_code<=16'hffff;state<=42'd1<<st_scan_map;
                end else begin cell_index<=next_cell;state<=42'd1<<st_map_read;end
                state[st_glyph_code]:state<=42'd1<<st_glyph_code_wait;
                state[st_glyph_code_wait]:begin current_code<=mem_read_data;state<=42'd1<<st_glyph_slot;end
                state[st_glyph_slot]:state<=42'd1<<st_glyph_slot_wait;
                state[st_glyph_slot_wait]:begin cache_slot<=mem_read_data[6:0];state<=42'd1<<st_glyph_id;end
                state[st_glyph_id]:state<=42'd1<<st_glyph_id_wait;
                state[st_glyph_id_wait]:begin glyph_id<=mem_read_data;state<=42'd1<<st_glyph_target;end
                state[st_glyph_target]:begin
                    target_sector<=11'd513+{1'd0,glyph_id[12:3]};
                    crc_kind<=2;crc_base<={1'b0,glyph_id[2:0],5'd0};crc_last<=31;state<=42'd1<<st_need_block;
                end
                state[st_clear_tag]:state<=42'd1<<st_row_read;
                state[st_row_read]:state<=42'd1<<st_row_wait;
                state[st_row_wait]:begin row_value<=mem_read_data;state<=42'd1<<st_row_write;end
                state[st_row_write]:if(row_index==15)state<=42'd1<<st_tag_write;
                    else begin row_index<=row_index+1'b1;state<=42'd1<<st_row_read;end
                state[st_tag_write]:state<=42'd1<<st_glyph_next;
                state[st_glyph_next]:if(descriptor_index+6'd1==descriptor_count)state<=42'd1<<st_close;
                    else begin descriptor_index<=descriptor_index+1'b1;state<=42'd1<<st_glyph_code;end
                state[st_close]:if(file_finished)begin session_open<=0;state<=42'd1<<st_finish;end
                state[st_finish]:begin done<=1;state<=42'd1<<st_idle;end
                state[st_retry]:begin retry<=1;state<=42'd1<<st_idle;end
                default:fail_proc(8'h88);
            endcase
            if(enable && file_finished && file_cancelled)begin
                session_open<=0;state<=error_code==0 ? 42'd1<<st_retry : 42'd1<<st_finish;
            end
            if(!enable)state<=42'd1<<st_idle;
            if(restart)occupied_slots<=0;
            else if(slot_reserve)occupied_slots[slot_write_index]<=1;
        end
    end
endmodule
