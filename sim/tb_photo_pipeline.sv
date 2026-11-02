`timescale 1ns/1ps
module tb_photo_pipeline;
    integer result_file;
    initial result_file=$fopen("tb_photo_pipeline.result","w");
    localparam integer width_val=640, height_val=480, image_words=307200;
    localparam integer bmp_size=921654, file_sectors=1801;
    reg clk=0, pix_clk=0, rst_n=0, start=0;
    always #4 clk=~clk;
    always #20 pix_clk=~pix_clk;
    integer scenario=0, volume_lba=0, cycle_tick=0, write_count=0;
    wire [31:0] data_start=volume_lba+2080;
    wire sector_req, fs_busy, fs_done;
    wire [31:0] sector_lba;
    reg sector_busy=0, sector_valid=0, sector_done=0;
    reg [7:0] sector_data=0, sector_error=0;
    reg [8:0] sector_index=0;
    integer model_state=0, model_index=0;
    reg [31:0] model_lba;
    wire [7:0] fs_error, bmp_error, load_error;
    wire [3:0] resource_valid, image_complete;
    wire [1:0] image_index;
    wire file_start, file_valid, file_end, pixel_valid, top_down, frame_commit, load_done;
    wire [31:0] file_size, file_offset;
    wire [7:0] file_data;
    wire [23:0] pixel_data;
    wire app_wr_en;
    wire [20:0] app_wr_addr;
    wire [31:0] app_wr_data;
    wire [3:0] app_wr_mask;
    wire controller_busy=(cycle_tick % 997) < 9;
    wire refresh_active=(cycle_tick % 997) < 9;
    reg [31:0] frame_mem [0:image_words*4-1];
    bit written_flag [0:image_words*4-1];
    photo_fat32 fs_proc (
        .file_cancel(1'b0),.file_cancelled(),
        .clk(clk),.rst_n(rst_n),.start(start),.busy(fs_busy),.done(fs_done),
        .error_code(fs_error),.resource_valid(resource_valid),.image_index(image_index),
        .sector_req(sector_req),.sector_lba(sector_lba),.sector_busy(sector_busy),
        .sector_valid(sector_valid),.sector_data(sector_data),.sector_index(sector_index),
        .sector_done(sector_done),.sector_error(sector_error),
        .file_start(file_start),.file_size(file_size),.file_valid(file_valid),
        .file_data(file_data),.file_offset(file_offset),.file_end(file_end),
        .load_done(load_done),.load_error(load_error),.decode_error(bmp_error)
    );
    photo_bmp_decoder bmp_proc (
        .clk(clk),.rst_n(rst_n),.file_start(file_start),.file_size(file_size),
        .file_valid(file_valid),.file_data(file_data),.file_offset(file_offset),
        .file_end(file_end),.upstream_error(fs_error),.pixel_valid(pixel_valid),
        .pixel_data(pixel_data),.top_down(top_down),.frame_commit(frame_commit),.error_code(bmp_error)
    );
    photo_frame_loader load_proc (
        .clk(clk),.rst_n(rst_n),.load_start(file_start),.image_index(image_index),
        .pixel_valid(pixel_valid),.pixel_data(pixel_data),.top_down(top_down),
        .frame_commit(frame_commit),.load_end(file_end),.load_cancel(1'b0),.decode_error(bmp_error),.upstream_error(fs_error),
        .controller_ready(1'b1),.controller_busy(controller_busy),.refresh_active(refresh_active),
        .load_busy(),.load_done(load_done),.image_complete(image_complete),.error_code(load_error),
        .app_wr_en(app_wr_en),.app_wr_addr(app_wr_addr),.app_wr_data(app_wr_data),.app_wr_mask(app_wr_mask)
    );
    function automatic [23:0] expected_pixel(input integer image, input integer x, input integer y);
        expected_pixel={8'(x),8'(y),8'((image*53) ^ x ^ y)};
    endfunction
    function automatic [7:0] bmp_byte(input integer image, input integer offset);
        integer p,x,y,h;
        reg [23:0] rgb;
        begin
            bmp_byte=0;
            h=(image & 1) ? -height_val : height_val;
            if (offset==0) bmp_byte="B";
            else if (offset==1) bmp_byte="M";
            else if (offset>=2 && offset<6) bmp_byte=bmp_size >> ((offset-2)*8);
            else if (offset==10) bmp_byte=54;
            else if (offset==14) bmp_byte=40;
            else if (offset>=18 && offset<22) bmp_byte=width_val >> ((offset-18)*8);
            else if (offset>=22 && offset<26) bmp_byte=h >> ((offset-22)*8);
            else if (offset==26) bmp_byte=1;
            else if (offset==28) bmp_byte=24;
            else if (offset==30 && (scenario==3 || scenario==8 ||
                     (scenario==7 && image==0) || (scenario==9 && image==1))) bmp_byte=1;
            else if (offset>=54 && offset<bmp_size) begin
                p=(offset-54)/3; x=p%width_val; y=p/width_val;
                if (!(image & 1)) y=height_val-1-y;
                rgb=expected_pixel(image,x,y);
                case ((offset-54)%3)
                    0: bmp_byte=rgb[7:0]; 1: bmp_byte=rgb[15:8]; 2: bmp_byte=rgb[23:16];
                endcase
            end
        end
    endfunction
    function automatic [31:0] fat_value(input integer cluster);
        integer image,delta;
        begin
            fat_value=32'h0fffffff;
            if (cluster==2) fat_value=scenario==2 ? 2 : 4;
            if (scenario==4 && cluster==127) fat_value=127;
            for (image=0;image<4;image=image+1) begin
                delta=cluster-(10+image*10000);
                if (delta>=0 && delta%2==0 && delta/2<file_sectors-1)
                    fat_value=cluster+2;
            end
            if (scenario==6 && cluster==10) fat_value=10;
        end
    endfunction
    function automatic [7:0] disk_byte(input integer lba,input integer offset);
        integer cluster,image,delta,entry,pos;
        reg [31:0] value;
        begin
            disk_byte=0;
            if (volume_lba!=0 && lba==0) begin
                if (offset==450) disk_byte=8'h0c;
                if (offset>=454 && offset<458) disk_byte=volume_lba >> ((offset-454)*8);
                if (offset>=458 && offset<462) disk_byte=131072 >> ((offset-458)*8);
                if (offset==510) disk_byte=8'h55;
                if (offset==511) disk_byte=8'haa;
            end else if (lba==volume_lba) begin
                case (offset)
                    0: disk_byte=8'heb; 11: disk_byte=0; 12: disk_byte=2;
                    13: disk_byte=1; 14: disk_byte=32; 16: disk_byte=2;
                    32,33,34,35: disk_byte=131072 >> ((offset-32)*8);
                    34: disk_byte=2; 37: disk_byte=4; 44: disk_byte=scenario==4 ? 127 : 2;
                    510: disk_byte=8'h55; 511: disk_byte=8'haa;
                endcase
            end else if (lba>=volume_lba+32 && lba<volume_lba+1056) begin
                cluster=(lba-volume_lba-32)*128+offset/4;
                value=fat_value(cluster); disk_byte=value >> ((offset%4)*8);
            end else if (lba==data_start+(scenario==4 ? 125 : 0)) begin
                if (offset%32==0) disk_byte=8'he5;
            end else if (lba==data_start+2) begin
                entry=offset/32; pos=offset%32;
                if (entry<4) begin
                    case (pos)
                        0: disk_byte="P"; 1: disk_byte="I"; 2: disk_byte="C";
                        3: disk_byte="1"+entry;
                        4,5,6,7: disk_byte=" ";
                        8: disk_byte="B"; 9: disk_byte="M"; 10: disk_byte="P";
                        11: disk_byte=8'h21;
                        20,21: disk_byte=(10+entry*10000) >> (16+(pos-20)*8);
                        26,27: disk_byte=(10+entry*10000) >> ((pos-26)*8);
                        28,29,30,31: disk_byte=bmp_size >> ((pos-28)*8);
                    endcase
                end
            end else begin
                cluster=lba-data_start+2;
                for (image=0;image<4;image=image+1) begin
                    delta=cluster-(10+image*10000);
                    if (delta>=0 && delta%2==0 && delta/2<file_sectors)
                        disk_byte=bmp_byte(image,delta/2*512+offset);
                end
            end
        end
    endfunction
    always @(posedge clk) begin
        if (!rst_n) begin
            model_state<=0; sector_busy<=0; sector_valid<=0; sector_done<=0;
            sector_error<=0; cycle_tick<=0;
        end else begin
            cycle_tick<=cycle_tick+1; sector_valid<=0; sector_done<=0;
            case(model_state)
                0: if(sector_req) begin
                    sector_busy<=1; model_lba<=sector_lba; model_index<=0; model_state<=1;
                end
                1: begin
                    sector_valid<=1; sector_data<=disk_byte(model_lba,model_index);
                    sector_index<=model_index;
                    if(model_index==511) model_state<=2;
                    else model_index<=model_index+1;
                end
                2: begin
                    sector_done<=1; sector_busy<=0; model_state<=0;
                    sector_error<=scenario==5 ? 8'h15 : 0;
                end
            endcase
            if(app_wr_en) begin
                if (app_wr_addr>=image_words*4 || app_wr_mask!=0)
                    $fatal(1,"write address/mask invalid");
                if (app_wr_data !== {8'd0,expected_pixel(app_wr_addr/image_words,
                    (app_wr_addr%image_words)%width_val,(app_wr_addr%image_words)/width_val)})
                    $fatal(1,"pixel mismatch address=%0d got=%h",app_wr_addr,app_wr_data);
                if (written_flag[app_wr_addr]) $fatal(1,"duplicate pixel address=%0d",app_wr_addr);
                written_flag[app_wr_addr]=1;
                frame_mem[app_wr_addr]<=app_wr_data; write_count=write_count+1;
            end
        end
    end
    reg display_ready=0;
    wire [1:0] display_index, active_index;
    wire frame_commit_read, auto_mode, request_busy, timer_en;
    wire [7:0] player_error;
    reg next_down=0, prev_down=0, auto_down=0;
    reg [16:0] ms_tick=0;
    wire tick_1ms=timer_en && ms_tick==124999;
    always @(posedge clk) begin
        if (!rst_n || !timer_en || tick_1ms) ms_tick<=0;
        else ms_tick<=ms_tick+1'b1;
    end
    photo_player_control #(.auto_period_ms(5)) player_proc (
        .clk(clk),.rst_n(rst_n),.enable(display_ready),.tick_1ms(tick_1ms),
        .next_down(next_down),.prev_down(prev_down),.auto_down(auto_down),
        .frame_commit(frame_commit_read),.active_index(active_index),
        .valid_mask(image_complete),
        .image_index(display_index),.auto_mode(auto_mode),
        .request_busy(request_busy),.timer_en(timer_en),.error_code(player_error)
    );
    wire read_req, read_ack, read_en, app_rd_en, underflow_flag, frame_ready;
    wire [20:0] app_rd_addr;
    wire [31:0] read_data;
    reg [11:0] return_valid=0;
    reg [20:0] return_addr [0:11];
    wire [7:0] read_error;
    wire hs_0,vs_0,de_0,hs,vs,de;
    wire [23:0] video_data;
    integer j;
    always @(posedge clk) begin
        if (!rst_n) return_valid<=0;
        else begin
            return_valid<={return_valid[10:0],app_rd_en};
            return_addr[0]<=app_rd_addr;
            for(j=1;j<12;j=j+1) return_addr[j]<=return_addr[j-1];
        end
    end
    photo_frame_reader reader_proc (
        .mem_clk(clk),.mem_rst_n(rst_n),.pix_clk(pix_clk),.pix_rst_n(rst_n),
        .display_ready(display_ready),.image_index(display_index),.controller_ready(1'b1),
        .controller_busy(controller_busy),.refresh_active(refresh_active),
        .app_rd_en(app_rd_en),.app_rd_addr(app_rd_addr),
        .sdram_rd_valid(return_valid[11]),.sdram_rd_data(frame_mem[return_addr[11]]),
        .frame_sync(vs_0),.read_req(read_req),.read_req_ack(read_ack),.read_en(read_en),.read_data(read_data),
        .underflow_flag(underflow_flag),.error_code(read_error),
        .frame_ready(frame_ready),
        .frame_commit(frame_commit_read),.active_index(active_index)
    );
    video_timing_data timing_proc (
        .video_clk(pix_clk),.rst(!rst_n),.read_req(read_req),.read_req_ack(read_ack),
        .hs(hs_0),.vs(vs_0),.de(de_0)
    );
    video_delay delay_proc (
        .video_clk(pix_clk),.rst(!rst_n),.read_en(read_en),.read_data(read_data[23:0]),
        .hs(hs_0),.vs(vs_0),.de(de_0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(video_data)
    );
    reg video_check=0;
    integer display_count=0,display_frames=0;
    integer expected_bank [0:6]='{0,1,0,3,0,1,2};
    always @(negedge pix_clk) begin
        if (read_ack && display_ready) video_check=1;
        if (video_check && de) begin
            if (!frame_ready) begin
                $fdisplay(result_file,"FAIL active video without frame_ready frame=%0d pixel=%0d time=%0t",
                    display_frames,display_count,$time);
                $fclose(result_file);
                $fatal(1,"active video started before frame prefetch");
            end
            if (underflow_flag || read_error!=0) begin
                $fdisplay(result_file,"FAIL reader error=%h underflow=%b frame=%0d pixel=%0d time=%0t",
                    read_error,underflow_flag,display_frames,display_count,$time);
                $fclose(result_file);
                $fatal(1,"reader error=%h underflow=%b",read_error,underflow_flag);
            end
            if (video_data !== expected_pixel(expected_bank[display_frames],
                display_count%width_val,display_count/width_val)) begin
                $fdisplay(result_file,"FAIL video frame=%0d pixel=%0d got=%h expected=%h state=%0d used=%0d empty=%b issued=%0d returned=%0d",
                    display_frames,display_count,video_data,expected_pixel(expected_bank[display_frames],
                    display_count%width_val,display_count/width_val),reader_proc.state,
                    reader_proc.fifo_used,reader_proc.fifo_empty,reader_proc.issued_count,reader_proc.returned_count);
                $fclose(result_file);
                $fatal(1,"video alignment frame=%0d pixel=%0d got=%h expected=%h",
                    display_frames,display_count,video_data,expected_pixel(expected_bank[display_frames],
                    display_count%width_val,display_count/width_val));
            end
            display_count=display_count+1;
            if (display_count==image_words) begin
                display_count=0; display_frames=display_frames+1;
                if(display_frames==7) video_check=0;
            end
        end
    end
    task automatic control_event_proc(input integer kind);
        begin
            @(negedge clk); next_down=kind==0; prev_down=kind==1; auto_down=kind==2;
            @(negedge clk); next_down=0; prev_down=0; auto_down=0;
        end
    endtask
    task automatic run_case(input integer case_val,input integer partition_val);
        integer k;
        begin
            @(negedge clk); rst_n=0; start=0; display_ready=0;
            scenario=case_val; volume_lba=partition_val;
            write_count=0;
            for(k=0;k<image_words*4;k=k+1) written_flag[k]=0;
            repeat(8) @(negedge clk); rst_n=1;
            repeat(4) @(negedge clk); start=1;
            @(negedge clk); start=0;
            wait(fs_done); @(negedge clk);
        end
    endtask
    initial begin
        if ($test$plusargs("reader_only")) begin
            for (integer k=0;k<image_words*4;k=k+1)
                frame_mem[k]={8'd0,expected_pixel(k/image_words,k%width_val,(k%image_words)/width_val)};
            repeat(8) @(negedge clk); rst_n=1;
            #25000000;
        end else begin
            run_case(0,0);
            if(fs_error!=0 || image_complete!=15 || write_count!=image_words*4)
            $fatal(1,"four-frame load failed fs=%h bmp=%h mem=%h writes=%0d complete=%h",
                   fs_error,bmp_error,load_error,write_count,image_complete);
            $fdisplay(result_file,"PASS four 640x480 frames: fragmented files, root chain, both orientations, all pixels");
        end
        display_ready=1;
        wait(display_frames==0 && display_count==1000); control_event_proc(0);
        wait(display_frames==1 && display_count==1000); control_event_proc(1);
        wait(display_frames==2 && display_count==1000); control_event_proc(1);
        wait(display_frames==3 && display_count==1000); control_event_proc(0);
        wait(display_frames==4 && display_count==1000); control_event_proc(2);
        wait(display_frames==7);
        $fdisplay(result_file,"PASS official FIFO/video: seven complete frames, mid-frame commands, next/previous wraps, auto");
        video_check=0;
        run_case(2,0);
        if(fs_error!=8'h26 || image_complete!=0) $fatal(1,"root loop not rejected: %h",fs_error);
        $fdisplay(result_file,"PASS root FAT loop rejected");
        run_case(4,0);
        if(fs_error!=8'h26 || image_complete!=0) $fatal(1,"last FAT entry loop not rejected: %h",fs_error);
        $fdisplay(result_file,"PASS last FAT sector entry (cluster 127) loop rejected");
        run_case(5,0);
        if(fs_error!=8'h20 || image_complete!=0) $fatal(1,"coincident sector done/error lost: %h",fs_error);
        $fdisplay(result_file,"PASS coincident sector done/error propagated");
        run_case(6,0);
        if(fs_error!=8'h26 || image_complete!=0) $fatal(1,"file FAT loop not rejected: %h",fs_error);
        $fdisplay(result_file,"PASS file FAT loop rejected without frame commit");
        run_case(3,2048);
        if(fs_error!=0 || resource_valid!=0 || image_complete!=0 || bmp_error!=8'h33)
            $fatal(1,"MBR/all-bad exit failed fs=%h resource=%h complete=%h bmp=%h",
                   fs_error,resource_valid,image_complete,bmp_error);
        $fdisplay(result_file,"PASS MBR partition and all-bad BMP exit");
        run_case(9,0);
        if(fs_error!=0 || resource_valid!=4'hd || image_complete!=4'hd ||
           write_count!=image_words*3)
            $fatal(1,"one bad image was not skipped fs=%h resource=%h complete=%h writes=%0d",
                   fs_error,resource_valid,image_complete,write_count);
        $fdisplay(result_file,"PASS one bad BMP skipped, three committed banks preserved");
        expected_bank[0]=0; expected_bank[1]=2; expected_bank[2]=3;
        display_frames=0; display_count=0; video_check=0; display_ready=1;
        wait(display_frames==0 && display_count==1000);
        control_event_proc(0);
        wait(display_frames==0 && display_count==2000);
        if(player_error!=8'he5 || display_index!=0 || request_busy)
            $fatal(1,"partial-mask bad target did not hold bank0 error=%h index=%0d busy=%b",
                   player_error,display_index,request_busy);
        control_event_proc(0);
        wait(display_frames==1 && display_count==1000);
        if(display_index!=2 || active_index!=2)
            $fatal(1,"partial-mask second press did not select bank2 index=%0d active=%0d",
                   display_index,active_index);
        control_event_proc(0);
        wait(display_frames==2 && display_count==1000);
        if(display_index!=3 || active_index!=3)
            $fatal(1,"partial-mask next valid did not select bank3 index=%0d active=%0d",
                   display_index,active_index);
        video_check=0; display_ready=0;
        $fdisplay(result_file,"PASS partial-mask reader bank0->bank2->bank3 video path");
        run_case(8,0);
        if(fs_error!=0 || resource_valid!=0 || image_complete!=0)
            $fatal(1,"all bad images did not produce an empty mask fs=%h resource=%h complete=%h",
                   fs_error,resource_valid,image_complete);
        $fdisplay(result_file,"PASS all bad BMPs terminate with no committed bank");
        $fdisplay(result_file,"PASS tb_photo_pipeline"); $fclose(result_file);
        $finish;
    end
    initial begin
        #2000000000;
        $fdisplay(result_file,"FAIL watchdog state=%0d fs=%h image=%0d root=%b cluster=%0d next=%0d fat=%h visited=%0d load=%b loaderr=%h bmp=%b bmperr=%h resource=%h complete=%h reader=%0d error=%h underflow=%b frames=%0d pixel=%0d",
            fs_proc.state,fs_error,fs_proc.image_index,fs_proc.root_flag,fs_proc.current_cluster,
            fs_proc.next_cluster,fs_proc.fat_entry,fs_proc.visited_count,load_done,load_error,
            bmp_proc.active_flag,bmp_error,resource_valid,image_complete,reader_proc.state,
            read_error,underflow_flag,display_frames,display_count);
        $fclose(result_file);
        $fatal(1,"pipeline watchdog");
    end
endmodule
