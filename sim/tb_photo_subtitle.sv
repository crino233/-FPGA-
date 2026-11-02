`timescale 1ns/1ps
module tb_photo_subtitle;
    reg mem_clk=0,clk=0,rst_n=0;
    always #4 mem_clk=~mem_clk;
    always #20 clk=~clk;
    reg file_start=0,file_valid=0,file_end=0,file_finished=0,file_cancelled=0;
    reg [31:0] file_size=0,file_offset=0;
    reg [7:0] file_data=0,file_error=0;
    wire file_request,load_done,ready,mem_en,mem_write_en;
    wire [1:0] file_index;
    wire [7:0] load_error,error_code;
    wire [4:0] notice_length,teacher_length;
    reg [6:0] character_map[0:63];
    wire [10:0] mem_addr;
    wire [15:0] mem_write_data,mem_read_data;
    always @(posedge mem_clk)if(mem_en && mem_write_en)begin
        if(mem_addr>=1472 && mem_addr<1536)character_map[mem_addr-1472]=mem_write_data[6:0];
        else if(mem_addr<1408 || mem_addr>=1472)$fatal(1,"subtitle write touched font ROM");
    end
    reg [7:0] text_bytes[0:127];
    reg [15:0] font_rows[0:2047];
    integer result_file,fd,n,position,old_pos,other_pos,expected_length;
    reg vs=1,de=0,frame_sync=1,frame_commit=0,menu_active=0,subtitle_enable=1,underflow_flag=0;
    reg [3:0] active_index=1;
    reg [1:0] scene_mode=0;
    reg [2:0] subtitle_speed=2,subtitle_alpha=1;
    reg [23:0] rgb_in=24'h80c0fc;
    wire [23:0] rgb_out;
    photo_subtitle_load dut(
        .clk(mem_clk),.rst_n(rst_n),.enable(1'b1),.file_request(file_request),.file_index(file_index),
        .file_start(file_start),.file_valid(file_valid),.file_end(file_end),.file_finished(file_finished),
        .file_cancelled(file_cancelled),.file_size(file_size),.file_offset(file_offset),.file_data(file_data),
        .file_error(file_error),.load_done(load_done),.load_error(load_error),.ready(ready),.error_code(error_code),
        .notice_length(notice_length),.teacher_length(teacher_length),
        .mem_en(mem_en),.mem_write_en(mem_write_en),.mem_addr(mem_addr),.mem_write_data(mem_write_data),.mem_read_data(mem_read_data));
    photo_badge_overlay overlay_proc(
        .mem_clk(mem_clk),.mem_rst_n(rst_n),.clk(clk),.rst_n(rst_n),.vs(vs),.de(de),.rgb_in(rgb_in),
        .frame_sync(frame_sync),.frame_commit(frame_commit),.active_index(active_index),
        .video_visible(1'b1),.underflow_flag(underflow_flag),.menu_active(menu_active),.menu_item(3'd5),
        .manual_notice(1'b0),
        .music_volume(3'd4),.brightness_level(3'd4),.eye_mode(2'd0),
        .transition_mode(2'd0),.transition_alpha(8'hff),.transition_wipe_active(1'b0),.transition_wipe_ramp(5'd0),
        .slideshow_seconds(5'd5),.scene_mode(scene_mode),.exam_started(1'b0),.exam_running(1'b0),
        .exam_finished(1'b0),.exam_duration_index(3'd0),.exam_minutes(8'd30),.exam_second(6'd0),
        .subtitle_enable(subtitle_enable),.subtitle_speed(subtitle_speed),.subtitle_alpha(subtitle_alpha),
        .subtitle_ready(ready),.subtitle_notice_length(notice_length),.subtitle_teacher_length(teacher_length),
        .subtitle_mem_en(mem_en),.subtitle_mem_write_en(mem_write_en),.subtitle_mem_addr(mem_addr),
        .subtitle_mem_write_data(mem_write_data),.subtitle_mem_read_data(mem_read_data),
        .rgb_out(rgb_out),.overlay_active(),.frame_start_out(),.visible_index_out(),.visible_valid_out(),
        .incoming_valid_out(),.incoming_index_out());
    reg [10:0] check_addr=0;
    reg [6:0] check_index=0;
    wire [15:0] check_row,check_code;
    photo_subtitle_ram font_check_proc(
        .mem_clk(mem_clk),.mem_en(1'b1),.mem_write_en(1'b0),.mem_addr(11'd1280+{4'd0,check_index}),.mem_write_data(16'd0),.mem_read_data(check_code),
        .pix_clk(clk),.read_en(1'b1),.read_addr(check_addr),.read_data(check_row));
    task reset_proc;
        begin
            @(negedge mem_clk);rst_n=0;file_start=0;file_valid=0;file_end=0;file_finished=0;file_error=0;file_cancelled=0;
            repeat(6)@(negedge mem_clk);rst_n=1;repeat(3)@(negedge mem_clk);
        end
    endtask
    task send_proc(input integer length,input bit cancel);
        begin
            wait(file_request);@(negedge mem_clk);file_start=1;file_size=length;file_offset=0;
            @(negedge mem_clk);file_start=0;
            for(integer i=0;i<length;i=i+1)begin
                file_valid=1;file_offset=i;file_data=text_bytes[i];@(negedge mem_clk);
            end
            file_valid=0;repeat(3)@(negedge mem_clk);
            file_end=1;file_cancelled=cancel;@(negedge mem_clk);file_end=0;
            repeat(4)@(negedge mem_clk);file_finished=1;
            @(negedge mem_clk);file_finished=0;repeat(4)@(negedge mem_clk);file_cancelled=0;
        end
    endtask
    task text_proc(input string filename);
        begin
            fd=$fopen(filename,"rb");if(!fd)$fatal(1,"missing fixture %s",filename);
            n=$fread(text_bytes,fd);$fclose(fd);send_proc(n,0);
        end
    endtask
    task compare_text_proc(input string filename,input bit teacher);
        integer count,offset,code,slot;
        begin
            fd=$fopen(filename,"rb");n=$fread(text_bytes,fd);$fclose(fd);count=0;offset=0;
            while(offset<n && text_bytes[offset]!=10 && text_bytes[offset]!=13)begin
                if(text_bytes[offset]<128)begin code=text_bytes[offset];offset=offset+1;end
                else begin code=((text_bytes[offset]&15)<<12)|((text_bytes[offset+1]&63)<<6)|(text_bytes[offset+2]&63);offset=offset+3;end
                slot=character_map[(teacher ? 32 : 0)+count];
                if(slot>=80 || font_rows[1280+slot]!=code)$fatal(1,"edited TXT glyph mapping page=%b cell=%0d code=%h",teacher,count,code);
                count=count+1;
            end
            if((teacher ? teacher_length : notice_length)!=count)$fatal(1,"edited TXT length");
        end
    endtask
    task pixel_proc(input bit enabled);
        begin @(posedge clk);de<=enabled;#1;end
    endtask
    task boundary_proc;
        begin
            @(negedge clk);vs=0;frame_sync=0;repeat(5)pixel_proc(0);
            @(negedge clk);vs=1;frame_sync=1;repeat(100)pixel_proc(0);
        end
    endtask
    task commit_proc(input [3:0] index);
        begin
            @(negedge mem_clk);active_index=index;frame_commit=1;
            @(negedge mem_clk);frame_commit=0;repeat(10)pixel_proc(0);
            boundary_proc();repeat(4)pixel_proc(1);repeat(4)pixel_proc(0);
        end
    endtask
    task raster_proc(input string filename);
        integer image_file,dx,cell_index,slot,hits,page_base,text_length;
        reg [23:0] expected;
        begin
            boundary_proc();position=overlay_proc.subtitle_scroll;
            page_base=overlay_proc.subtitle_group ? 32 : 0;text_length=overlay_proc.subtitle_length;
            image_file=$fopen(filename,"wb");$fwrite(image_file,"P6\n640 480\n255\n");hits=0;
            for(integer y=0;y<480;y=y+1)begin
                for(integer x=0;x<640;x=x+1)begin
                    pixel_proc(1);expected=rgb_in;
                    if(x>=16 && x<624 && y>=440 && y<472)begin
                        expected={8'(int'(rgb_in[23:16])*subtitle_alpha/4),8'(int'(rgb_in[15:8])*subtitle_alpha/4),8'(int'(rgb_in[7:0])*subtitle_alpha/4)};
                        dx=x+position-624;
                        if(y>=448 && y<464 && dx>=0 && dx<text_length*16)begin
                            cell_index=page_base+dx/16;slot=character_map[cell_index];
                            if(font_rows[slot*16+y-448][15-dx%16])begin expected=24'heef3f5;hits=hits+1;end
                        end
                    end
                    if(rgb_out!==expected)$fatal(1,"subtitle raster x=%0d y=%0d alpha=%0d got=%h expected=%h",x,y,subtitle_alpha,rgb_out,expected);
                    $fwrite(image_file,"%c%c%c",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
                end
                repeat(5)pixel_proc(0);
            end
            $fclose(image_file);if(hits<100)$fatal(1,"subtitle text absent");
        end
    endtask
    initial begin #500000000;$fatal(1,"subtitle watchdog");end
    initial begin
        result_file=$fopen("tb_photo_subtitle.result","w");$readmemh("photo_subtitle_font.dath",font_rows);
        for(integer i=0;i<2048;i=i+1)begin
            @(negedge clk);check_addr=i;@(posedge clk);#1;
            if(check_row!==font_rows[i])$fatal(1,"native internal BRAM32K row %0d",i);
        end
        for(integer i=0;i<80;i=i+1)begin
            @(negedge mem_clk);check_index=i;@(posedge mem_clk);#1;
            if(check_code!==font_rows[1280+i])$fatal(1,"native Unicode directory %0d",i);
        end
        for(integer card=0;card<2;card=card+1)begin
            reset_proc();
            text_proc(card ? "fixtures/card_b/NOTICE.TXT" : "fixtures/card_a/NOTICE.TXT");
            text_proc(card ? "fixtures/card_b/TEACHER.TXT" : "fixtures/card_a/TEACHER.TXT");
            wait(ready || error_code);if(error_code)$fatal(1,"subtitle load %h",error_code);
            compare_text_proc(card ? "fixtures/card_b/NOTICE.TXT" : "fixtures/card_a/NOTICE.TXT",0);
            compare_text_proc(card ? "fixtures/card_b/TEACHER.TXT" : "fixtures/card_a/TEACHER.TXT",1);
            commit_proc(1);repeat(1200)boundary_proc();
            raster_proc($sformatf("work/subtitle_card_%0d_notice.ppm",card));
            commit_proc(4);repeat(1200)boundary_proc();
            raster_proc($sformatf("work/subtitle_card_%0d_teacher.ppm",card));
        end
        $fdisplay(result_file,"PASS native 2048x16 BRAM32K rows/80 Unicode entries; real TF card A/B TXT mappings and four exact subtitle rasters, maximum 26 characters");
        commit_proc(1);menu_active=1;repeat(5)boundary_proc();old_pos=overlay_proc.notice_scroll;
        repeat(8)boundary_proc();if(overlay_proc.notice_scroll!=old_pos)$fatal(1,"menu pause");
        menu_active=0;repeat(5)boundary_proc();old_pos=overlay_proc.notice_scroll;
        commit_proc(2);if(overlay_proc.notice_scroll<old_pos)$fatal(1,"same group restart");
        for(integer speed=0;speed<5;speed=speed+1)begin
            menu_active=1;repeat(5)boundary_proc();old_pos=overlay_proc.notice_scroll;
            subtitle_speed=speed;repeat(6)boundary_proc();
            if(overlay_proc.notice_scroll!=old_pos)$fatal(1,"speed adjustment reset position");
            menu_active=0;repeat(5)boundary_proc();old_pos=overlay_proc.notice_scroll;
            repeat(16)boundary_proc();
            if(overlay_proc.notice_scroll-old_pos!=(speed==0 ? 2 : speed==1 ? 4 : speed==2 ? 8 : speed==3 ? 16 : 32))$fatal(1,"subtitle speed %0d",speed);
        end
        subtitle_speed=4;repeat(6)boundary_proc();old_pos=overlay_proc.notice_scroll;
        repeat(600)begin
            boundary_proc();old_pos=(old_pos+2)%1024;
            if(overlay_proc.notice_scroll!=old_pos)$fatal(1,"26 character wrap");
        end
        subtitle_speed=2;repeat(6)boundary_proc();
        for(integer alpha=0;alpha<5;alpha=alpha+1)begin
            subtitle_alpha=alpha;repeat(5)boundary_proc();raster_proc($sformatf("work/subtitle_alpha_%0d.ppm",alpha));
        end
        subtitle_alpha=1;repeat(5)boundary_proc();commit_proc(4);old_pos=overlay_proc.notice_scroll;
        repeat(10)boundary_proc();if(overlay_proc.notice_scroll!=old_pos)$fatal(1,"independent page position");
        other_pos=overlay_proc.teacher_scroll;commit_proc(1);
        if(overlay_proc.teacher_scroll<other_pos || overlay_proc.teacher_scroll>other_pos+1)$fatal(1,"page handoff");
        other_pos=overlay_proc.teacher_scroll;repeat(8)boundary_proc();
        if(overlay_proc.teacher_scroll!=other_pos)$fatal(1,"page restore");
        scene_mode=2;repeat(5)boundary_proc();old_pos=overlay_proc.notice_scroll;
        repeat(8)boundary_proc();if(overlay_proc.notice_scroll!=old_pos || overlay_proc.subtitle_visible)$fatal(1,"fire hide/pause");
        scene_mode=0;repeat(5)boundary_proc();subtitle_enable=0;repeat(5)boundary_proc();
        if(overlay_proc.notice_scroll!=0 || overlay_proc.teacher_scroll!=0)$fatal(1,"off reset");
        subtitle_enable=1;repeat(5)boundary_proc();if(overlay_proc.notice_scroll>3)$fatal(1,"on restart");
        $fdisplay(result_file,"PASS five scroll speeds/five opacity exact rasters, page/menu/safety pause, same-group retention, off/on restart");
        reset_proc();for(integer i=0;i<27;i=i+1)text_bytes[i]="A";send_proc(27,0);
        wait(error_code);if(error_code!=8'h84 || ready)$fatal(1,"27 characters accepted");
        reset_proc();text_bytes[0]=8'he0;text_bytes[1]=8'h80;text_bytes[2]=8'h80;send_proc(3,0);
        wait(error_code);if(error_code!=8'h83)$fatal(1,"overlong UTF-8");
        reset_proc();text_bytes[0]=8'hed;text_bytes[1]=8'ha0;text_bytes[2]=8'h80;send_proc(3,0);
        wait(error_code);if(error_code!=8'h83)$fatal(1,"surrogate");
        reset_proc();text_bytes[0]=8'he6;text_bytes[1]=8'hb5;send_proc(2,0);
        wait(error_code);if(error_code!=8'h83)$fatal(1,"truncated UTF-8");
        reset_proc();text_bytes[0]=8'hf0;text_bytes[1]=8'h9f;text_bytes[2]=8'h98;text_bytes[3]=8'h80;send_proc(4,0);
        wait(error_code);if(error_code!=8'h83)$fatal(1,"four-byte UTF-8");
        reset_proc();text_bytes[0]=8'he6;text_bytes[1]=8'hb5;text_bytes[2]=8'hb7;send_proc(3,0);
        wait(error_code);if(error_code!=8'h87 || ready)$fatal(1,"unsupported glyph");
        reset_proc();text_bytes[0]=8'hef;text_bytes[1]=8'hbb;text_bytes[2]=8'hbf;text_bytes[3]="A";
        text_bytes[4]=13;text_bytes[5]=10;send_proc(6,1);
        wait(file_request);if(file_index!=0)$fatal(1,"cancel retry file");
        send_proc(6,0);send_proc(0,0);wait(ready || error_code);
        if(error_code || notice_length!=1 || teacher_length!=0)$fatal(1,"BOM/CRLF short/empty");
        reset_proc();send_proc(0,0);send_proc(0,0);wait(ready || error_code);
        if(error_code || notice_length!=0 || teacher_length!=0)$fatal(1,"empty pair");
        reset_proc();for(integer i=0;i<26;i=i+1)text_bytes[i]=i[0] ? "0" : "A";
        send_proc(26,0);send_proc(26,0);wait(ready || error_code);
        if(error_code || notice_length!=26 || teacher_length!=26)$fatal(1,"editable 26/26 recombination");
        $fdisplay(result_file,"PASS 26/26 edited text, empty/short/BOM/CRLF/cancellation retry; 27/overlong/surrogate/truncated/four-byte/unsupported rejection");
        $fdisplay(result_file,"PASS tb_photo_subtitle");$fclose(result_file);$finish;
    end
endmodule
