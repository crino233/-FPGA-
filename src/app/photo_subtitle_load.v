`timescale 1ns/1ps
module photo_subtitle_load #(parameter integer external_font=0) (
    input wire clk, input wire rst_n, input wire enable,
    output wire file_request, output wire [1:0] file_index,
    output wire [31:0] range_offset, output wire file_close,
    input wire file_start, input wire file_valid, input wire file_end,
    input wire file_finished, input wire file_cancelled,
    input wire [31:0] file_size, input wire [31:0] file_offset,
    input wire [7:0] file_data, input wire [7:0] file_error,
    output reg load_done, output wire [7:0] load_error,
    output reg ready, output reg [7:0] error_code,
    output reg [4:0] notice_length, output reg [4:0] teacher_length,
    output wire mem_en, output wire mem_write_en, output wire [10:0] mem_addr,
    output wire [15:0] mem_write_data, input wire [15:0] mem_read_data
);
    localparam [3:0] st_request=0,st_text=1,st_text_end=2,st_read=3,st_read_wait=4,
        st_lookup=5,st_compare=6,st_map=7,st_done=8,st_external=9;
    reg [3:0] state;
    reg [6:0] lookup_index;
    reg selected_file;
    reg [4:0] text_count,char_index;
    reg [1:0] utf_left,utf_kind;
    reg [15:0] utf_code,code_value,current_character;
    reg code_valid,line_end;
    reg [7:0] parse_error;
    reg stream_start,stream_valid,stream_end,stream_finished,stream_cancelled;
    reg [31:0] stream_size,stream_offset;
    reg [7:0] stream_data;
    reg missing_flag,character_missing;
    wire font_request,font_close,font_done,font_retry,font_mem_en,font_mem_write_en;
    wire [31:0] font_offset;
    wire [7:0] font_error;
    wire [10:0] font_mem_addr;
    wire [15:0] font_mem_write_data;
    wire [5:0] map_index={selected_file,char_index};
    assign file_request=state==st_external ? font_request : enable && state==st_request;
    assign file_index=state==st_external ? 2'd2 : {1'b0,selected_file};
    assign range_offset=state==st_external ? font_offset : 32'd0;
    assign file_close=state==st_external && font_close;
    assign load_error=state==st_external ? font_error : parse_error;
    wire character_write=code_valid && parse_error==0 && code_value!=16'hfeff && !line_end && text_count<26;
    assign mem_en=state==st_external ? font_mem_en : character_write || state==st_read || state==st_lookup || state==st_map;
    assign mem_write_en=state==st_external ? font_mem_write_en : character_write || state==st_map;
    assign mem_addr=state==st_external ? font_mem_addr :
        character_write ? 11'd1408+{5'd0,selected_file,text_count} : state==st_read ? 11'd1408+{5'd0,selected_file,char_index} :
        state==st_map ? 11'd1472+{5'd0,map_index} : 11'd1280+{4'd0,lookup_index};
    assign mem_write_data=state==st_external ? font_mem_write_data : character_write ? code_value :
        character_missing ? 16'hffff : {9'd0,lookup_index};
    generate if(external_font)begin: external_proc
        photo_subtitle_font_load font_proc(.clk(clk),.rst_n(rst_n),.enable(state==st_external),
            .notice_length(notice_length),.teacher_length(teacher_length),
            .pin_valid(state==st_compare && mem_read_data==current_character),.pin_index(lookup_index),
            .restart(state==st_request && !selected_file),
            .file_request(font_request),.range_offset(font_offset),.file_close(font_close),
            .file_start(stream_start),.file_valid(stream_valid),.file_end(stream_end),
            .file_finished(stream_finished),.file_cancelled(stream_cancelled),
            .file_size(stream_size),.file_offset(stream_offset),.file_data(stream_data),.file_error(file_error),
            .done(font_done),.retry(font_retry),.error_code(font_error),
            .mem_en(font_mem_en),.mem_write_en(font_mem_write_en),.mem_addr(font_mem_addr),
            .mem_write_data(font_mem_write_data),.mem_read_data(mem_read_data));
    end else begin: internal_proc
        assign font_request=0;assign font_offset=0;assign font_close=0;assign font_done=0;assign font_retry=0;
        assign font_error=0;assign font_mem_en=0;assign font_mem_write_en=0;assign font_mem_addr=0;assign font_mem_write_data=0;
    end endgenerate
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            stream_start<=0;stream_valid<=0;stream_end<=0;stream_finished<=0;stream_cancelled<=0;
            stream_size<=0;stream_offset<=0;stream_data<=0;
        end else begin
            stream_start<=file_start;stream_valid<=file_valid;stream_end<=file_end;
            stream_finished<=file_finished;stream_cancelled<=file_cancelled;
            stream_size<=file_size;stream_offset<=file_offset;stream_data<=file_data;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=st_request;selected_file<=0;text_count<=0;char_index<=0;
            utf_left<=0;utf_kind<=0;utf_code<=0;code_value<=0;code_valid<=0;line_end<=0;
            current_character<=0;parse_error<=0;load_done<=0;ready<=0;error_code<=0;notice_length<=0;teacher_length<=0;lookup_index<=0;
            missing_flag<=0;character_missing<=0;
        end else begin
            load_done<=0;code_valid<=0;
            if(stream_start && state!=st_external)begin
                parse_error<=stream_size>128 ? 8'h82 : 0;utf_left<=0;utf_kind<=0;utf_code<=0;
                line_end<=0;text_count<=0;state<=st_text;
            end
            if(state==st_text && stream_valid && parse_error==0)begin
                if(utf_left!=0)begin
                    if(stream_data[7:6]!=2'b10)parse_error<=8'h83;
                    else if(utf_left==2)begin
                        if((utf_kind==0 && stream_data<8'ha0) || (utf_kind==3 && stream_data>=8'ha0))parse_error<=8'h83;
                        utf_code<={utf_code[9:0],stream_data[5:0]};utf_left<=1;
                    end else begin code_value<={utf_code[9:0],stream_data[5:0]};code_valid<=1;utf_left<=0;end
                end else if(stream_data<8'h80)begin
                    if(stream_data==13 || stream_data==10)line_end<=1;
                    else if(stream_data<32 || line_end)parse_error<=8'h83;
                    else begin code_value<={8'd0,stream_data};code_valid<=1;end
                end else if(stream_data>=8'hc2 && stream_data<=8'hdf)begin
                    utf_code<={11'd0,stream_data[4:0]};utf_left<=1;utf_kind<=1;
                end else if(stream_data>=8'he0 && stream_data<=8'hef)begin
                    utf_code<={12'd0,stream_data[3:0]};utf_left<=2;
                    utf_kind<=stream_data==8'he0 ? 0 : stream_data==8'hed ? 3 : 2;
                end else parse_error<=8'h83;
            end
            if(code_valid && parse_error==0)begin
                if(code_value==16'hfeff && text_count==0 && stream_offset<=3)begin end
                else if(line_end || code_value==16'hfeff || text_count==26)parse_error<=8'h84;
                else text_count<=text_count+1'b1;
            end
            if(stream_end)begin load_done<=1;if(state!=st_external)state<=st_text_end;end
            case(state)
                st_text_end:if(stream_finished)begin
                    if(stream_cancelled && parse_error==0)state<=st_request;
                    else if(file_error!=0 || parse_error!=0 || utf_left!=0)begin
                        error_code<=file_error!=0 ? file_error : parse_error!=0 ? parse_error : 8'h83;state<=st_done;
                    end else begin
                        if(selected_file)teacher_length<=text_count;else notice_length<=text_count;
                        char_index<=0;
                        if(text_count!=0)state<=st_read;
                        else if(selected_file)begin state<=missing_flag ? st_external : st_done;ready<=!missing_flag;end
                        else begin selected_file<=1;state<=st_request;end
                    end
                end
                st_read:state<=st_read_wait;
                st_read_wait:begin current_character<=mem_read_data;lookup_index<=0;character_missing<=0;state<=st_lookup;end
                st_lookup:state<=st_compare;
                st_compare:begin
                    if(mem_read_data==current_character)state<=st_map;
                    else if(lookup_index==79)begin
                        if(external_font)begin missing_flag<=1;character_missing<=1;state<=st_map;end
                        else begin error_code<=8'h87;state<=st_done;end
                    end
                    else begin lookup_index<=lookup_index+1'b1;state<=st_lookup;end
                end
                st_map:begin
                    if(char_index+5'd1==text_count)begin
                        if(selected_file)begin state<=missing_flag ? st_external : st_done;ready<=!missing_flag;end
                        else begin selected_file<=1;state<=st_request;end
                    end else begin char_index<=char_index+1'b1;state<=st_read;end
                end
                st_external:begin
                    if(font_retry)begin
                        selected_file<=0;missing_flag<=0;character_missing<=0;
                        notice_length<=0;teacher_length<=0;state<=st_request;
                    end else if(font_done)begin ready<=font_error==0;error_code<=font_error;state<=st_done;end
                end
            endcase
        end
    end
endmodule
