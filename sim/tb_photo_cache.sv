`timescale 1ns/1ps
module tb_photo_cache #(parameter integer group_prefetch=0);
    reg clk=0, rst_n=0, catalog_ready=0;
    always #4 clk=~clk;
    reg [9:0] valid_mask=10'h3bd;
    reg [9:0] selection_mask=10'h3ff;
    reg [3:0] requested_index=0, bank_complete=0;
    reg [1:0] active_bank=0;
    reg [11:0] load_source_width=640,load_source_height=480;
    reg file_done=0, auto_mode=0,display_publish_enable=1;
    wire file_request, display_ready,target_ready;
    wire [3:0] file_index, display_index, active_index, cache_valid;
    wire [1:0] load_bank, display_bank;
    wire [11:0] active_source_width,active_source_height;
    photo_cache_control #(.group_prefetch(group_prefetch)) dut (
        .clk(clk),.rst_n(rst_n),.catalog_ready(catalog_ready),.valid_mask(valid_mask),
        .requested_index(requested_index),.active_bank(active_bank),.auto_mode(auto_mode),
        .display_publish_enable(display_publish_enable),
        .selection_mask(selection_mask),
        .load_source_width(load_source_width),.load_source_height(load_source_height),
        .file_done(file_done),.file_cancelled(1'b0),.bank_complete(bank_complete),.file_request(file_request),
        .file_cancel(),
        .file_index(file_index),.load_bank(load_bank),.display_ready(display_ready),
        .display_bank(display_bank),.display_index(display_index),.active_index(active_index),
        .active_source_width(active_source_width),.active_source_height(active_source_height),
        .cache_valid(cache_valid),.target_ready(target_ready)
    );
    reg in_flight=0;
    integer pending_index, pending_bank, requests=0, result_file, evicted_index;
    always @(posedge clk) begin
        if(!rst_n) in_flight<=0;
        else begin
            if(display_ready && (!cache_valid[display_bank] || dut.cache_index[display_bank]!=display_index))
                $fatal(1,"published bank/index are inconsistent");
            if(file_done) in_flight<=0;
            if(file_request) begin
                if(in_flight || cache_valid[load_bank]) $fatal(1,"invalid load transaction");
                if(!valid_mask[file_index]) $fatal(1,"requested a known invalid file");
                if(display_ready && (load_bank==active_bank || load_bank==display_bank))
                    $fatal(1,"evicting an active or published slot");
                in_flight<=1;pending_index=file_index;pending_bank=load_bank;requests=requests+1;
            end
        end
    end
    task automatic finish_load(input integer image, input bit good=1);
        begin
            wait(in_flight);
            if(pending_index!=image) $fatal(1,"load %0d expected %0d",pending_index,image);
            @(negedge clk);
            load_source_width=1000+image*10;load_source_height=500+image;
            bank_complete[pending_bank]=good;file_done=1;
            if(!good) valid_mask[image]=0;
            @(negedge clk);file_done=0;
            wait(!in_flight);
            if(good && (dut.cache_source_width[pending_bank]!==1000+image*10 ||
                dut.cache_source_height[pending_bank]!==500+image))
                $fatal(1,"BMP source dimensions were not committed with cache slot %0d",pending_bank);
        end
    endtask
    function automatic integer resident_slot(input integer image);
        begin
            resident_slot=-1;
            for(integer i=0;i<4;i=i+1)
                if(cache_valid[i] && dut.cache_index[i]==image) resident_slot=i;
        end
    endfunction
    task automatic commit_display;
        begin
            @(negedge clk);active_bank=display_bank;
            repeat(2) @(negedge clk);
            if(active_source_width!==dut.cache_source_width[active_bank] ||
                active_source_height!==dut.cache_source_height[active_bank])
                $fatal(1,"active source dimensions do not follow the committed image slot");
        end
    endtask
    task automatic quiet_cache;
        integer before_requests;
        begin
            wait(dut.state==7);
            before_requests=requests;
            repeat(100) @(negedge clk);
            if(in_flight || requests!=before_requests || dut.state!=7)
                $fatal(1,"filled cache did not stop file requests");
        end
    endtask
    task automatic reset_cache(input reg [9:0] mask, input bit automatic_mode);
        begin
            @(negedge clk);rst_n=0;catalog_ready=0;file_done=0;
            repeat(4) @(negedge clk);
            valid_mask=mask;auto_mode=automatic_mode;requested_index=0;
            active_bank=0;bank_complete=0;requests=0;rst_n=1;catalog_ready=1;
        end
    endtask
    task automatic hit_request(input integer image);
        begin
            @(negedge clk);requested_index=image;
            repeat(2) @(negedge clk);
            if(!display_ready || display_index!=image)
                $fatal(1,"cached request blocked by background load: wanted %0d got %0d",image,display_index);
        end
    endtask
    initial begin
        result_file=$fopen(group_prefetch ? "tb_photo_cache_group.result" : "tb_photo_cache.result","w");
        if(group_prefetch)begin
            selection_mask=10'h00e;reset_cache(10'h3ff,1);requested_index=1;
            finish_load(1);wait(display_ready);commit_display();
            finish_load(2);finish_load(3);quiet_cache();
            if(requests!=3)$fatal(1,"notice prefetch escaped its group");
            hit_request(3);commit_display();hit_request(1);commit_display();hit_request(2);commit_display();quiet_cache();
            if(requests!=3)$fatal(1,"notice forward/reverse reloaded a resident photo");
            @(negedge clk);selection_mask=10'h0f0;requested_index=4;
            finish_load(4);wait(display_index==4);commit_display();
            finish_load(5);finish_load(6);finish_load(7);quiet_cache();
            if(requests!=7 || cache_valid!=15)$fatal(1,"culture did not fill exactly four group slots");
            hit_request(7);commit_display();hit_request(4);commit_display();hit_request(6);commit_display();
            hit_request(5);commit_display();quiet_cache();
            if(requests!=7)$fatal(1,"culture navigation repeated a TF read");
            @(negedge clk);selection_mask=10'h200;requested_index=9;
            finish_load(9);wait(display_index==9);commit_display();quiet_cache();
            if(requests!=8)$fatal(1,"fire single-picture group triggered unrelated prefetch");
            @(negedge clk);selection_mask=10'h00e;requested_index=1;display_publish_enable=0;
            finish_load(1);
            repeat(100)@(negedge clk);
            if(!target_ready || display_index!=9 || !in_flight || pending_index!=2)
                $fatal(1,"group prefetch stalled behind transition publication: ready=%b display=%0d flight=%b index=%0d",
                    target_ready,display_index,in_flight,pending_index);
            finish_load(2);
            if(display_index!=9)$fatal(1,"group prefetch published through a closed transition gate");
            @(negedge clk);display_publish_enable=1;
            repeat(2)@(negedge clk);
            if(display_index!=1)$fatal(1,"prepared group target did not publish on release");
            commit_display();finish_load(3);quiet_cache();
            @(negedge clk);selection_mask=10'h0f0;requested_index=7;display_publish_enable=0;
            finish_load(7);finish_load(4);finish_load(5);
            repeat(100)@(negedge clk);
            if(display_index!=1 || resident_slot(7)<0 || resident_slot(4)<0 || resident_slot(5)<0)
                $fatal(1,"prepared reverse target stopped group scan at the old published picture");
            @(negedge clk);display_publish_enable=1;
            repeat(2)@(negedge clk);commit_display();finish_load(6);quiet_cache();
            if(resident_slot(4)<0 || resident_slot(5)<0 || resident_slot(6)<0 || resident_slot(7)<0)
                $fatal(1,"group did not finish after transition released the old slot");
            @(negedge clk);selection_mask=10'h200;requested_index=9;
            wait(in_flight);evicted_index=dut.cache_index[pending_bank];
            if(evicted_index<4 || evicted_index>7)$fatal(1,"full-group eviction fixture missing");
            finish_load(9);wait(display_index==9);commit_display();quiet_cache();
            @(negedge clk);selection_mask=10'h0f0;requested_index=evicted_index;
            repeat(100)@(negedge clk);
            if(!in_flight || pending_index!=evicted_index)
                $fatal(1,"same-group protection blocked the requested miss after fire");
            finish_load(evicted_index);wait(display_index==evicted_index);commit_display();
            $fdisplay(result_file,"PASS requested miss may evict a non-visible same-group slot after fire preemption");
            $fdisplay(result_file,"PASS same-group prefetch overlaps a prepared target's fade-out without publishing early");
            $fdisplay(result_file,"PASS notice 3/culture 4/fire 1: group-only prefetch, two-clock bidirectional resident hits, safe eviction and idle TF stop");
            $fdisplay(result_file,"PASS tb_photo_cache_group");$fclose(result_file);$finish;
        end
        repeat(4) @(negedge clk);rst_n=1;catalog_ready=1;
        finish_load(0);wait(display_ready);
        finish_load(2);
        @(negedge clk);requested_index=2;
        wait(in_flight);
        if(pending_index!=3) $fatal(1,"manual mode did not prefetch two ahead");
        hit_request(0);hit_request(2);hit_request(0);hit_request(2);
        if(!in_flight || pending_index!=3) $fatal(1,"hit cancelled the issued file");
        commit_display();finish_load(3);finish_load(4);quiet_cache();
        if(resident_slot(0)<0 || resident_slot(2)<0 || resident_slot(3)<0 || resident_slot(4)<0)
            $fatal(1,"current/previous/next/two-ahead window not retained");
        $fdisplay(result_file,"PASS resident hits within two clocks during a stalled file; rapid forward/reverse requests");

        hit_request(3);commit_display();
        wait(dut.state==4 && dut.replace_index==resident_slot(0));
        hit_request(0);
        if(in_flight || resident_slot(0)<0 || requests!=4)
            $fatal(1,"newly requested resident slot was evicted");
        commit_display();quiet_cache();
        hit_request(3);commit_display();
        wait(in_flight);
        if(pending_index!=5 || resident_slot(0)<0 || resident_slot(4)<0 || resident_slot(2)>=0)
            $fatal(1,"eviction did not protect previous/first-ahead slots");
        finish_load(5);quiet_cache();
        if(resident_slot(0)<0 || resident_slot(3)<0 || resident_slot(4)<0 || resident_slot(5)<0)
            $fatal(1,"new cache window incorrect");
        $fdisplay(result_file,"PASS same-edge request/eviction collision and previous/first-ahead slot protection");

        reset_cache(10'h3ff,0);finish_load(0);wait(display_ready);
        @(negedge clk);requested_index=1;finish_load(1);wait(in_flight);
        if(pending_index!=2)$fatal(1,"manual prefetch fixture not stalled on PIC3");
        @(negedge clk);display_publish_enable=0;requested_index=0;
        repeat(2)@(negedge clk);
        if(!target_ready || display_index!=1 || !in_flight)
            $fatal(1,"prepared cache hit published before transition release ready=%b display=%0d target=%0d flight=%b bank=%0d cache=%b slots=%0d/%0d/%0d/%0d req=%h",
                target_ready,display_index,requested_index,in_flight,dut.state,cache_valid,
                dut.cache_index[0],dut.cache_index[1],dut.cache_index[2],dut.cache_index[3],dut.request_slots);
        @(negedge clk);display_publish_enable=1;
        repeat(2)@(negedge clk);
        if(display_index!=0 || !in_flight || pending_index!=2)
            $fatal(1,"transition release delayed a resident hit or cancelled prefetch");
        commit_display();finish_load(2);
        @(negedge clk);display_publish_enable=0;requested_index=9;
        repeat(2)@(negedge clk);
        if(target_ready || display_index!=0)$fatal(1,"cold target displaced the visible image");
        wait(in_flight);
        if(pending_index!=9)$fatal(1,"cold target request blocked by a later prefetch");
        finish_load(9);
        if(!target_ready || display_index!=0)$fatal(1,"cold target published before transition release");
        @(negedge clk);display_publish_enable=1;repeat(2)@(negedge clk);
        if(display_index!=9)$fatal(1,"cold target was not published after release");
        $fdisplay(result_file,"PASS transition gate preserves two-clock resident hits and holds the old image until a cold target is ready");

        reset_cache(10'h3bd,1);finish_load(0);wait(display_ready);finish_load(2);quiet_cache();
        if(requests!=2 || resident_slot(3)>=0) $fatal(1,"automatic mode over-prefetched");
        @(negedge clk);auto_mode=0;
        finish_load(3);quiet_cache();
        if(requests!=3) $fatal(1,"manual mode did not extend the window");
        @(negedge clk);auto_mode=1;quiet_cache();
        if(requests!=3) $fatal(1,"mode change reloaded a resident image");
        $fdisplay(result_file,"PASS automatic one-ahead/manual two-ahead, mode wakeup and idle TF stop");

        reset_cache(10'h001,0);finish_load(0);wait(display_ready);quiet_cache();
        if(requests!=1) $fatal(1,"single image reloaded");
        reset_cache(10'h201,0);finish_load(0);wait(display_ready);finish_load(9);quiet_cache();
        if(requests!=2) $fatal(1,"two-image window wrapped into duplicate loads");
        hit_request(9);commit_display();quiet_cache();hit_request(0);commit_display();quiet_cache();
        reset_cache(10'h205,0);finish_load(0);wait(display_ready);finish_load(2);finish_load(9);quiet_cache();
        if(requests!=3) $fatal(1,"three-image window wrapped into duplicate loads");
        $fdisplay(result_file,"PASS one/two/three valid images, sparse mask and PIC10 wrap without duplicate reads");

        reset_cache(10'h3ff,0);finish_load(0);wait(display_ready);
        finish_load(1,0);finish_load(2);finish_load(3);quiet_cache();
        if(valid_mask[1] || resident_slot(1)>=0 || resident_slot(0)<0 || requests!=4)
            $fatal(1,"failed prefetch was published or retried");
        $fdisplay(result_file,"PASS failed prefetch removed before rebuilding two-valid-image window");
        reset_cache(10'h3ff,0);finish_load(0,0);finish_load(1,0);finish_load(2);wait(display_ready);
        finish_load(3);finish_load(4);quiet_cache();
        if(display_index!=2 || requests!=5 || resident_slot(2)<0)
            $fatal(1,"invalid initial request displaced the first surviving image");
        commit_display();quiet_cache();
        $fdisplay(result_file,"PASS invalid initial request with delayed first reader commit");

        reset_cache(10'h3ff,0);requested_index=1;finish_load(1);wait(display_ready);
        if(display_index!=1 || resident_slot(0)>=0)
            $fatal(1,"requested startup image was not committed as the first display");
        $fdisplay(result_file,"PASS requested PIC2 startup is displayed before PIC1");
        $fdisplay(result_file,"PASS tb_photo_cache");$fclose(result_file);$finish;
    end
    initial begin #100000; $fatal(1,"cache test watchdog"); end
endmodule
