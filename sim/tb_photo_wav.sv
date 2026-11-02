`timescale 1ns/1ps
module tb_photo_wav #(parameter integer fault_mode=0);
    reg clk=0,pix_clk=0,rst_n=0;
    always #4 clk=~clk;always #20 pix_clk=~pix_clk;
    reg [7:0] corpus[0:10055];reg [15:0] expected[0:4999];
    initial begin $readmemh("work/wav_fixture.hex",corpus);$readmemh("work/wav_expected.hex",expected);end
    wire image_req,audio_req,card_req,client_busy,image_owner,audio_owner;
    wire [31:0] image_lba,audio_lba,card_lba;
    reg card_busy=0,card_valid=0,card_done=0;
    reg [7:0] card_data=0;reg [8:0] card_index=0;
    wire image_catalog,image_busy,image_done,image_available;
    wire audio_catalog,audio_busy,audio_done,audio_available;
    wire [7:0] image_error,audio_error,stream_error,load_error;
    reg image_request=0,image_load_done=0;
    wire audio_request,audio_pause,audio_load_done;
    wire image_start,image_valid,image_end,audio_start,audio_valid,audio_end;
    wire [31:0] image_size,image_offset,audio_size,audio_offset;
    wire [7:0] image_data,audio_data;
    wire urgent,sample_ready;wire signed [15:0] sample_data;
    reg play_enable=1,consume_enable=1;
    reg [2:0] sample_div=0;
    wire consume=consume_enable && sample_div==6;
    wire [31:0] written,underflows;
    integer result_file,images=0,samples=0,sectors=0,audio_loops=0;
    photo_sector_arbiter arb(.clk(clk),.rst_n(rst_n),.audio_urgent(urgent),
        .image_req(image_req),.image_lba(image_lba),.audio_req(audio_req),.audio_lba(audio_lba),
        .client_busy(client_busy),.card_req(card_req),.card_lba(card_lba),.card_busy(card_busy),
        .card_done(card_done),.image_owner(image_owner),.audio_owner(audio_owner));
    photo_fat32 #(.image_count(1),.index_bits(1),.request_mode(1)) image_fs(
        .clk(clk),.rst_n(rst_n),.start(rst_n && !image_catalog && !image_busy),.busy(image_busy),.done(image_done),
        .error_code(image_error),.resource_valid(image_available),.image_index(),.catalog_ready(image_catalog),
        .file_req(image_request),.file_req_index(1'b0),.file_cancel(1'b0),.file_pause(1'b0),.file_cancelled(),
        .aux_req(1'b0),.aux_index(2'd0),.aux_active(),.aux_available(),.aux_error(),
        .sector_req(image_req),.sector_lba(image_lba),.sector_busy(client_busy),
        .sector_valid(card_valid && image_owner),.sector_data(card_data),.sector_index(card_index),
        .sector_done(card_done && image_owner),.sector_error(8'd0),.file_start(image_start),.file_size(image_size),
        .file_valid(image_valid),.file_data(image_data),.file_offset(image_offset),.file_end(image_end),
        .load_done(image_load_done),.load_error(8'd0),.decode_error(8'd0));
    photo_fat32 #(.image_count(1),.index_bits(1),.request_mode(1),.audio_catalog(1),.pausable(1),.max_chain_clusters(8192)) audio_fs(
        .clk(clk),.rst_n(rst_n),.start(rst_n && !audio_catalog && !audio_busy),.busy(audio_busy),.done(audio_done),
        .error_code(audio_error),.resource_valid(audio_available),.image_index(),.catalog_ready(audio_catalog),
        .file_req(audio_request),.file_req_index(1'b0),.file_cancel(1'b0),.file_pause(audio_pause),.file_cancelled(),
        .aux_req(1'b0),.aux_index(2'd0),.aux_active(),.aux_available(),.aux_error(),
        .sector_req(audio_req),.sector_lba(audio_lba),.sector_busy(client_busy),
        .sector_valid(card_valid && audio_owner),.sector_data(card_data),.sector_index(card_index),
        .sector_done(card_done && audio_owner),.sector_error(8'd0),.file_start(audio_start),.file_size(audio_size),
        .file_valid(audio_valid),.file_data(audio_data),.file_offset(audio_offset),.file_end(audio_end),
        .load_done(audio_load_done),.load_error(load_error),.decode_error(8'd0));
    photo_wav_stream stream(.clk(clk),.rst_n(rst_n),.play_enable(play_enable),
        .catalog_ready(audio_catalog),.fs_busy(audio_busy),.fs_done(audio_done),.fs_error(audio_error),.available(audio_available),
        .file_request(audio_request),.file_pause(audio_pause),.load_done(audio_load_done),.load_error(load_error),
        .file_start(audio_start),.file_size(audio_size),.file_valid(audio_valid),.file_data(audio_data),
        .file_offset(audio_offset),.file_end(audio_end),.pix_clk(pix_clk),.pix_rst_n(rst_n),.consume(consume),
        .sample_data(sample_data),.sample_ready(sample_ready),.urgent(urgent),.error_code(stream_error),
        .samples_written(written),.underflows(underflows));
    function [7:0] disk_byte(input integer lba,input integer offset);
        integer cluster,pos,entry;reg [31:0] value;
        begin
            disk_byte=0;
            if(lba==0)case(offset)
                11:disk_byte=0;12:disk_byte=2;13:disk_byte=1;14:disk_byte=32;16:disk_byte=2;
                32,33,34,35:disk_byte=131072>>((offset-32)*8);
                37:disk_byte=4;44:disk_byte=2;510:disk_byte=8'h55;511:disk_byte=8'haa;
            endcase
            else if(lba>=32 && lba<1056)begin
                cluster=(lba-32)*128+offset/4;value=32'h0fffffff;
                if(cluster==10)value=11;
                if(cluster>=98020 && cluster<98058 && !(cluster%2))value=cluster+2;
                if(fault_mode==1 && cluster==98030)value=98020;
                disk_byte=value>>((offset%4)*8);
            end else if(lba==2080)begin
                entry=offset/32;pos=offset%32;
                if(entry<(fault_mode==2 ? 1 : 2))case(pos)
                    0,1,2,3,4,5,6,7,8,9,10:disk_byte=(entry==0 ? 88'h5049433120202020424d50 : 88'h42474d2020202020574156)>>(80-pos*8);
                    11:disk_byte=8'h20;
                    20,21:disk_byte=(entry==0 ? 10 : 98020)>>(16+(pos-20)*8);
                    26,27:disk_byte=(entry==0 ? 10 : 98020)>>((pos-26)*8);
                    28,29,30,31:disk_byte=(entry==0 ? 822 : 10056)>>((pos-28)*8);
                endcase
            end else if(lba==2088 || lba==2089)disk_byte=((lba-2088)*512+offset)^8'h5a;
            else if(lba>=100098 && lba<=100136 && !(lba%2))begin
                pos=((lba-100098)/2)*512+offset;if(pos<10056)disk_byte=corpus[pos];
            end
        end
    endfunction
    integer model_state=0,model_lba=0,model_index=0,delay_count=0;
    always @(posedge clk)begin
        card_valid<=0;card_done<=0;image_request<=0;image_load_done<=image_end;
        if(rst_n)begin
            if(image_catalog && !image_busy && !image_request && !image_done && images<30)image_request<=1;
            if(image_done)images<=images+1;
            if(audio_done)audio_loops<=audio_loops+1;
            if(image_valid && image_data!==((image_offset^32'h5a)&255))$fatal(1,"sector owner corrupted image %d",image_offset);
            if(image_error || (!fault_mode && (audio_error || stream_error)))$fatal(1,"FAT/WAV error %h %h %h state=%d offset=%d",image_error,audio_error,stream_error,stream.parse_state,audio_offset);
            if(image_owner && audio_owner)$fatal(1,"overlapping sector owners");
            case(model_state)
                0:if(card_req)begin card_busy<=1;model_lba<=card_lba;model_index<=0;delay_count<=sectors%37;sectors<=sectors+1;model_state<=1;end
                1:if(delay_count>0)delay_count<=delay_count-1;
                    else begin card_valid<=1;card_data<=disk_byte(model_lba,model_index);card_index<=model_index;
                        if(model_index==511)model_state<=2;else model_index<=model_index+1;end
                2:begin card_busy<=0;card_done<=1;model_state<=0;end
            endcase
        end
    end
    always @(posedge pix_clk)if(rst_n)begin
        sample_div<=sample_div==6 ? 0 : sample_div+1'b1;
        if(consume && sample_ready)begin
            if(sample_data!==expected[samples%5000])$fatal(1,"PCM order sample=%d expected=%h got=%h write=%d read=%d",samples,expected[samples%5000],sample_data,stream.write_ptr,stream.read_ptr);
            samples<=samples+1;
        end
    end
    initial begin
        result_file=$fopen(fault_mode==1 ? "tb_photo_wav_faults.result" : fault_mode==2 ? "tb_photo_wav_missing.result" : "tb_photo_wav.result","w");repeat(12)@(negedge clk);rst_n=1;
        if(fault_mode)begin
            wait(stream_error!=0);wait(images>=5);repeat(30)@(negedge pix_clk);
            if(image_error || sample_ready || (fault_mode==1 ? stream_error!=8'h93 || audio_error!=8'h26 : stream_error!=8'h90))$fatal(1,"audio fault isolation %h/%h",stream_error,audio_error);
            $fdisplay(result_file,"PASS missing BGM or cyclic FAT chain stops only WAV; image cursor continues, PCM stays silent");
            if(fault_mode==1)$fdisplay(result_file,"PASS tb_photo_wav_faults");
            else $fdisplay(result_file,"PASS tb_photo_wav_missing");
            $fclose(result_file);$finish;
        end
        wait(samples>=1000);consume_enable=0;repeat(10000)@(negedge pix_clk);
        if(stream.used_write>4096)$fatal(1,"ring overfill");
        consume_enable=1;wait(samples>=6000);play_enable=0;
        wait(!sample_ready);repeat(300)@(negedge pix_clk);play_enable=1;
        wait(samples>=12000);
        if(images<5 || audio_loops<2 || underflows==0)$fatal(1,"coverage images=%d loops=%d gaps=%d",images,audio_loops,underflows);
        $fdisplay(result_file,"PASS shared single-sector arbiter, two real FAT32 cursors, fragmented BGM cluster chain, image byte ownership");
        $fdisplay(result_file,"PASS odd RIFF chunk padding, signed samples/endian, 12000 ordered samples, ring wraps/full/backpressure, pause/underflow/refill and file loops");
        $fdisplay(result_file,"PASS tb_photo_wav");$fclose(result_file);$finish;
    end
    initial begin #100000000;$fatal(1,"WAV watchdog samples=%d images=%d fs=%d card=%d",samples,images,audio_fs.state,model_state);end
endmodule
