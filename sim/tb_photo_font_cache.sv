`timescale 1ns/1ps
module tb_photo_font_cache;
    reg clk=0,rst_n=0;
    always #4 clk=~clk;
    wire request,close_file,load_done,ready,mem_en,mem_write_en;
    wire [1:0] file_index;
    wire [31:0] range_offset;
    wire [7:0] error_code,load_error;
    wire [4:0] notice_length,teacher_length;
    wire [10:0] mem_addr;
    wire [15:0] mem_write_data,mem_read_data;
    reg file_start=0,file_valid=0,file_end=0,file_finished=0,file_cancelled=0;
    reg [31:0] file_size=0,file_offset=0;
    reg [7:0] file_data=0,file_error=0;
    reg [7:0] font[0:745215];
    reg [15:0] expected_codes[0:51];
    reg [15:0] code_pool[0:415];
    integer result_file,fd,font_bytes,scenario=0,requests=0,font_sectors=0;
    integer slot_index,code_index,glyph_index,byte_index;
    reg [10:0] check_addr=0;
    wire [15:0] check_data;
    always @(negedge clk)if(rst_n && !$onehot(dut.external_proc.font_proc.state))
        $fatal(1,"font cache state lost one-hot encoding");
    photo_subtitle_load #(.external_font(1)) dut(.*,
        .enable(1'b1),.file_request(request),.file_close(close_file));
    photo_subtitle_ram ram(.mem_clk(clk),.mem_en(mem_en),.mem_write_en(mem_write_en),
        .mem_addr(mem_addr),.mem_write_data(mem_write_data),.mem_read_data(mem_read_data),
        .pix_clk(clk),.read_en(1'b1),.read_addr(check_addr),.read_data(check_data));
    task read_proc(input integer address);
        begin @(negedge clk);check_addr=address;@(posedge clk);#1;end
    endtask
    task reset_proc;
        begin @(negedge clk);rst_n=0;repeat(6)@(negedge clk);rst_n=1;end
    endtask
    initial forever begin: server_proc
        integer index,start_pos,length,code,corrupt_pos;
        wait(rst_n && request);
        index=file_index;start_pos=range_offset;length=index==2 ? 512 : scenario==7 ? 0 : 78;
        @(negedge clk);file_start=1;file_size=index==2 ? font_bytes : length;file_offset=start_pos;
        @(negedge clk);file_start=0;requests=requests+1;
        if(index==2)font_sectors=font_sectors+1;
        for(integer i=0;i<length;i=i+1)begin
            file_valid=1;file_offset=start_pos+i;
            if(index==2)begin
                file_data=font[start_pos+i];
                if(scenario==1 && start_pos==0 && i==3)file_data=file_data^1;
                if(scenario==2 && start_pos>=512 && start_pos<262656 &&
                    i==(dut.external_proc.font_proc.current_code%128)*4)file_data=file_data^1;
                if(scenario==3 && start_pos>=262656 &&
                    i==(dut.external_proc.font_proc.glyph_id%8)*64+63)file_data=file_data^1;
            end else begin
                code=expected_codes[index*26+i/3];
                case(i%3)0:file_data=8'he0|(code>>12);1:file_data=8'h80|((code>>6)&63);2:file_data=8'h80|(code&63);endcase
            end
            @(negedge clk);file_valid=0;repeat(9)@(negedge clk);
        end
        file_end=1;@(negedge clk);file_end=0;
        wait(load_done);repeat(4)@(negedge clk);
        if(scenario==4 && index==2 && start_pos>=262656)begin file_cancelled=1;scenario=5;end
        file_finished=1;@(negedge clk);file_finished=0;file_cancelled=0;
        if(index==2)begin
            wait(request || close_file || !rst_n);
            if(close_file)begin repeat(4)@(negedge clk);file_finished=1;@(negedge clk);file_finished=0;end
        end
    end
    initial begin
        result_file=$fopen("tb_photo_font_cache.result","w");
        fd=$fopen("tf_card/FONT16.BIN","rb");font_bytes=$fread(font,fd);$fclose(fd);
        if(font_bytes!=745216)$fatal(1,"font fixture size");
        $readmemh("work/font_codes.hex",code_pool);
        for(integer i=0;i<52;i=i+1)expected_codes[i]=16'h4e00+i;
        for(integer trial=0;trial<8;trial=trial+1)begin
            scenario=trial;font_sectors=0;
            for(integer i=0;i<52;i=i+1)expected_codes[i]=code_pool[(trial==5 ? 4 : trial)*52+i];
            if(trial==6)expected_codes[0]=16'h9fff;
            reset_proc();wait(ready || error_code);
            if(trial==1 || trial==2)begin if(error_code!=8'h85 || ready)$fatal(1,"bad header/index %h",error_code);end
            else if(trial==3)begin if(error_code!=8'h86 || ready)$fatal(1,"bad glyph %h",error_code);end
            else if(trial==6)begin if(error_code!=8'h87 || ready)$fatal(1,"missing glyph %h",error_code);end
            else begin
                if(error_code || !ready)$fatal(1,"font cache scenario=%0d error=%h helper=%0d",trial,error_code,dut.external_proc.font_proc.state);
                if(trial==7)begin if(notice_length || teacher_length || font_sectors)$fatal(1,"empty reads font");end
                else begin
                    if(notice_length!=26 || teacher_length!=26)$fatal(1,"26/26 capacity");
                    for(integer i=0;i<52;i=i+1)begin
                        read_proc(1472+(i<26 ? i : i+6));slot_index=check_data;
                        if(slot_index>=80)$fatal(1,"slot bounds");
                        read_proc(1280+slot_index);if(check_data!=expected_codes[i])$fatal(1,"Unicode tag %0d got=%h",i,check_data);
                        glyph_index={font[512+expected_codes[i]*4],font[513+expected_codes[i]*4]};
                        for(integer row=0;row<16;row=row+1)begin
                            read_proc(slot_index*16+row);
                            byte_index=262656+glyph_index*64+2+row*2;
                            if(check_data!={font[byte_index],font[byte_index+1]})$fatal(1,"glyph pixels %0d row%0d",i,row);
                        end
                    end
                    if(trial==0 && font_sectors>105)$fatal(1,"font scanned instead of indexed");
                end
            end
            $fdisplay(result_file,"PASS scenario=%0d error=%h font_data_sectors=%0d",trial,error_code,font_sectors);
        end
        scenario=0;for(integer i=0;i<52;i=i+1)expected_codes[i]=code_pool[104+i];
        reset_proc();
        wait(dut.external_proc.font_proc.state[34] && dut.external_proc.font_proc.row_index==7);
        slot_index=dut.external_proc.font_proc.cache_slot;
        read_proc(1280+slot_index);
        if(check_data!=0 || ready)$fatal(1,"partial cache published before tag commit");
        reset_proc();wait(ready || error_code);
        if(error_code || notice_length!=26 || teacher_length!=26)$fatal(1,"mid-cache reset recovery");
        for(integer i=0;i<52;i=i+1)begin
            read_proc(1472+(i<26 ? i : i+6));slot_index=check_data;
            read_proc(1280+slot_index);if(check_data!=expected_codes[i])$fatal(1,"post-reset cache tag");
            glyph_index={font[512+expected_codes[i]*4],font[513+expected_codes[i]*4]};
            for(integer row=0;row<16;row=row+1)begin
                read_proc(slot_index*16+row);byte_index=262656+glyph_index*64+2+row*2;
                if(check_data!={font[byte_index],font[byte_index+1]})$fatal(1,"post-reset glyph row");
            end
        end
        $fdisplay(result_file,"PASS reset during partial glyph write, invalid tag and complete retry, all 52 glyphs checked");
        $fdisplay(result_file,"PASS tb_photo_font_cache");$fclose(result_file);$finish;
    end
    initial begin #100000000;$fatal(1,"font cache watchdog state=%0d helper=%0d error=%h",dut.state,dut.external_proc.font_proc.state,error_code);end
endmodule
