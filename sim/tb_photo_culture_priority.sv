`timescale 1ns/1ps
module tb_photo_culture_priority #(parameter integer prove_old=0);
    reg clk=0,rst_n=0,frame_commit=0,auto_step=0,prev_down=0,target_valid=0,file_done=0;
    reg [3:0] target_index=4,bank_complete=0;
    reg [1:0] active_bank=0;
    always #4 clk=~clk;
    wire [3:0] requested_index,active_index,display_index,file_index,cache_valid;
    wire [1:0] display_bank,load_bank;
    wire [11:0] active_source_width,active_source_height;
    wire request_busy,display_ready,file_request;
    reg in_flight=0;
    integer pending_index=0,pending_bank=0,result_file;
    photo_player_control #(.image_count(10),.external_control(1)) player(
        .clk(clk),.rst_n(rst_n),.enable(rst_n),.tick_1ms(1'b0),.next_down(1'b0),.prev_down(prev_down),
        .auto_down(1'b0),.frame_commit(frame_commit),.active_index(active_index),.valid_mask(10'h3ff),
        .external_auto(1'b1),.auto_step(auto_step),.discard_events(1'b0),.selection_mask(10'h0f0),
        .target_valid(target_valid),.target_index(target_index),.image_index(requested_index),.request_busy(request_busy));
    photo_cache_control #(.group_prefetch(1)) cache(
        .clk(clk),.rst_n(rst_n),.catalog_ready(rst_n),.valid_mask(10'h3ff),.requested_index(requested_index),
        .auto_mode(1'b1),.display_publish_enable(1'b1),.selection_mask(10'h0f0),.active_bank(active_bank),
        .load_source_width(12'd640),.load_source_height(12'd480),
        .file_done(file_done),.file_cancelled(1'b0),.bank_complete(bank_complete),.file_request(file_request),
        .file_index(file_index),.load_bank(load_bank),.display_ready(display_ready),.display_bank(display_bank),
        .display_index(display_index),.active_index(active_index),.active_source_width(active_source_width),
        .active_source_height(active_source_height),.cache_valid(cache_valid));
    always @(posedge clk)begin
        if(!rst_n)in_flight<=0;
        else begin
            if(file_done)in_flight<=0;
            if(file_request)begin
                if(in_flight)$fatal(1,"overlapping load");
                pending_index<=file_index;pending_bank<=load_bank;in_flight<=1;
            end
        end
    end
    task finish_proc(input integer image);
        begin
            wait(in_flight);if(pending_index!=image)$fatal(1,"prefetch sequence %0d !=%0d",pending_index,image);
            @(negedge clk);bank_complete[pending_bank]=1;file_done=1;
            @(negedge clk);file_done=0;wait(!in_flight);
        end
    endtask
    task commit_proc(input integer image);
        begin
            wait(display_index==image && display_ready);
            @(negedge clk);active_bank=display_bank;frame_commit=1;
            @(negedge clk);frame_commit=0;repeat(5)@(negedge clk);
        end
    endtask
    initial begin
        result_file=$fopen(prove_old ? "tb_photo_culture_old_queue.result" : "tb_photo_culture_priority.result","w");
        repeat(6)@(negedge clk);rst_n=1;
        finish_proc(4);commit_proc(4);finish_proc(5);
        @(negedge clk);target_index=5;target_valid=1;
        @(negedge clk);target_valid=0;commit_proc(5);
        wait(in_flight && pending_index==6);
        @(negedge clk);auto_step=1;@(negedge clk);auto_step=0;
        wait(requested_index==6 && request_busy);
        @(negedge clk);prev_down=1;@(negedge clk);prev_down=0;
        repeat(12)@(negedge clk);
        if(prove_old)begin
            if(requested_index!=6 || display_index!=5 || !player.manual_pending || !in_flight)
                $fatal(1,"old automatic-load manual blockage not reproduced");
            $fdisplay(result_file,"PASS old version queues manual previous behind an unfinished automatic PIC7 while PIC6 remains visible");
            $fdisplay(result_file,"PASS tb_photo_culture_old_queue");
        end else begin
            if(requested_index!=4 || display_index!=4 || !in_flight || pending_index!=6)
                $fatal(1,"resident manual previous blocked by cold auto target requested=%0d displayed=%0d",requested_index,display_index);
            commit_proc(4);if(request_busy)$fatal(1,"manual target commit not acknowledged");
            finish_proc(6);
            if(active_index!=4 || !cache_valid[active_bank])$fatal(1,"background completion damaged resident manual target");
            $fdisplay(result_file,"PASS PIC6 automatic cold-next wait can be interrupted by resident manual previous within 12 clocks, background load drains and visible slot remains protected");
            $fdisplay(result_file,"PASS tb_photo_culture_priority");
        end
        $fclose(result_file);$finish;
    end
    initial begin #100000;$fatal(1,"culture priority watchdog");end
endmodule
