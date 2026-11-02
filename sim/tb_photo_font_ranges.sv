`timescale 1ns/1ps
module tb_photo_font_ranges;
    reg clk=0,rst_n=0,start=0,aux_req=0,aux_close=0,file_cancel=0;
    reg [31:0] aux_offset=0;
    always #4 clk=~clk;
    wire busy,done,catalog_ready,aux_active,aux_block_done,req,file_start,file_valid,file_end,file_cancelled;
    wire [7:0] error_code,aux_error,file_data;
    wire [31:0] lba,file_size,file_offset;
    reg card_busy=0,card_valid=0,card_done=0;
    reg [7:0] card_data=0;
    reg [8:0] card_index=0;
    reg load_done=0;
    integer spc=1,fault_mode=0,result_file,blocks=0,data_reads=0,fat_reads=0;
    integer transfer_state=0,transfer_index=0,transfer_lba=0,expected_offset=0,seen_bytes=0;
    localparam integer data_base=131104,font_size=745216;
    function automatic integer cluster_proc(input integer ordinal);
        cluster_proc=4660+ordinal*3;
    endfunction
    function automatic [7:0] byte_proc(input integer address,input integer offset);
        integer cluster,ordinal,word_value,file_sector,pos;
        begin
            byte_proc=0;
            if(address==0)case(offset)
                12:byte_proc=2;13:byte_proc=spc;14:byte_proc=32;16:byte_proc=2;
                32,33,34,35:byte_proc=8388608>>((offset-32)*8);
                36,37,38,39:byte_proc=65536>>((offset-36)*8);
                44:byte_proc=2;510:byte_proc=8'h55;511:byte_proc=8'haa;
            endcase
            else if(address>=32 && address<65568)begin
                cluster=(address-32)*128+offset/4;word_value=32'h0fffffff;
                if(cluster>=4660 && (cluster-4660)%3==0)begin
                    ordinal=(cluster-4660)/3;
                    if((ordinal+1)*spc<(font_size+511)/512)word_value=cluster_proc(ordinal+1);
                    if(fault_mode==1 && ordinal==1)word_value=cluster_proc(0);
                end
                byte_proc=word_value>>((offset%4)*8);
            end else if(address==data_base)begin
                if(offset<32)case(offset)
                    0,1,2,3,4,5,6,7,8,9,10:byte_proc=88'h464f4e543136202042494e>>(80-offset*8);
                    11:byte_proc=8'h20;
                    20,21:byte_proc=4660>>(16+(offset-20)*8);
                    26,27:byte_proc=4660>>((offset-26)*8);
                    28,29,30,31:byte_proc=font_size>>((offset-28)*8);
                endcase
            end else if(address>=data_base+(4660-2)*spc)begin
                cluster=2+(address-data_base)/spc;ordinal=(cluster-4660)/3;
                file_sector=ordinal*spc+(address-data_base)%spc;
                byte_proc=(file_sector*512+offset)^((file_sector*512+offset)>>9)^8'ha7;
            end
        end
    endfunction
    photo_fat32 #(.image_count(1),.index_bits(1),.request_mode(1),.auxiliary_files(1),.font_ranges(1)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),.error_code(error_code),.catalog_ready(catalog_ready),
        .file_req(1'b0),.file_req_index(1'b0),.file_cancel(file_cancel),.file_pause(1'b0),.file_cancelled(file_cancelled),
        .aux_req(aux_req),.aux_index(2'd2),.aux_offset(aux_offset),.aux_close(aux_close),
        .aux_active(aux_active),.aux_block_done(aux_block_done),.aux_error(aux_error),
        .sector_req(req),.sector_lba(lba),.sector_busy(card_busy),.sector_valid(card_valid),
        .sector_data(card_data),.sector_index(card_index),.sector_done(card_done),.sector_error(8'd0),
        .file_start(file_start),.file_size(file_size),.file_valid(file_valid),.file_data(file_data),
        .file_offset(file_offset),.file_end(file_end),.load_done(load_done),.load_error(8'd0),.decode_error(8'd0));
    always @(posedge clk)begin
        card_valid<=0;card_done<=0;load_done<=file_end;
        if(!rst_n)begin transfer_state<=0;card_busy<=0;load_done<=0;end
        else case(transfer_state)
            0:if(req)begin
                transfer_lba<=lba;transfer_index<=0;card_busy<=1;transfer_state<=1;
                if(lba>=32 && lba<65568)fat_reads=fat_reads+1;
                else if(lba!=0 && lba!=data_base)data_reads=data_reads+1;
            end
            1:begin
                card_valid<=1;card_index<=transfer_index;card_data<=byte_proc(transfer_lba,transfer_index);
                if(transfer_index==511)transfer_state<=2;else transfer_index<=transfer_index+1;
            end
            2:begin card_done<=1;card_busy<=0;transfer_state<=0;end
        endcase
        if(rst_n && file_valid)begin
            if(file_offset!=expected_offset+seen_bytes ||
                file_data!==8'((file_offset)^(file_offset>>9)^8'ha7))
                $fatal(1,"range payload spc=%0d offset=%0d expected=%0d data=%h",spc,file_offset,expected_offset+seen_bytes,file_data);
            seen_bytes=seen_bytes+1;
        end
    end
    task reset_proc;
        begin
            @(negedge clk);rst_n=0;aux_req=0;aux_close=0;file_cancel=0;
            repeat(6)@(negedge clk);rst_n=1;start=1;
            @(negedge clk);start=0;wait(catalog_ready);@(negedge clk);
            if(error_code)$fatal(1,"catalog error %h",error_code);
        end
    endtask
    task range_proc(input integer offset);
        begin
            @(negedge clk);aux_offset=offset;aux_req=1;expected_offset=offset;seen_bytes=0;
            wait(file_start);@(negedge clk);aux_req=0;
            wait(aux_block_done || done);
            if(done || aux_error)$fatal(1,"range failed offset%0d aux=%h",offset,aux_error);
            @(negedge clk);
            if(seen_bytes!=(font_size-offset<512 ? font_size-offset : 512))$fatal(1,"range length %0d",seen_bytes);
            blocks=blocks+1;
        end
    endtask
    initial begin
        result_file=$fopen("tb_photo_font_ranges.result","w");
        for(integer pass=0;pass<3;pass=pass+1)begin
            spc=pass==0 ? 1 : pass==1 ? 2 : 64;data_reads=0;fat_reads=0;reset_proc();
            range_proc(0);range_proc(512);range_proc(255*512);range_proc(513*512);range_proc(1455*512);
            @(negedge clk);aux_close=1;wait(done);@(negedge clk);aux_close=0;
            if(data_reads!=5)$fatal(1,"skipped font data fetched spc=%0d reads=%0d",spc,data_reads);
            $fdisplay(result_file,"PASS spc=%0d fragmented forward seek, final partial sector, data_reads=%0d FAT_reads=%0d",spc,data_reads,fat_reads);
        end
        spc=1;fault_mode=1;reset_proc();range_proc(0);
        @(negedge clk);aux_offset=255*512;aux_req=1;wait(file_start);@(negedge clk);aux_req=0;
        wait(done);if(aux_error!=8'h26)$fatal(1,"range skipped loop protection %h",aux_error);
        $fdisplay(result_file,"PASS exact loop detection remains active across skipped data clusters");
        fault_mode=0;reset_proc();range_proc(0);
        @(negedge clk);file_cancel=1;wait(done);
        if(!file_cancelled)$fatal(1,"idle font session cancel");
        $fdisplay(result_file,"PASS tb_photo_font_ranges");$fclose(result_file);$finish;
    end
    initial begin #100000000;$fatal(1,"range watchdog state=%0d error=%h",dut.state,aux_error);end
endmodule
