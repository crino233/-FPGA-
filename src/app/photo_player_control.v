`timescale 1ns/1ps
module photo_player_control #(
    parameter integer auto_period_ms = 5000,
    parameter integer image_count = 4,
    parameter integer index_bits = $clog2(image_count),
    parameter integer external_control = 0
) (
    input wire clk, input wire rst_n, input wire enable,
    input wire tick_1ms, input wire next_down, input wire auto_down, input wire prev_down,
    input wire frame_commit, input wire [index_bits-1:0] active_index,
    input wire [image_count-1:0] valid_mask,
    input wire external_auto, input wire auto_step, input wire discard_events,
    input wire [image_count-1:0] selection_mask,
    input wire target_valid, input wire [index_bits-1:0] target_index,
    output reg [index_bits-1:0] image_index, output reg auto_mode,
    output reg request_busy, output wire timer_en, output reg [7:0] error_code
);
    localparam integer auto_bits = auto_period_ms > 1 ? $clog2(auto_period_ms) : 1;
    reg [auto_bits-1:0] auto_tick;
    reg manual_pending, pending_prev, manual_bad_pending, bad_prev;
    reg search_flag, search_prev, search_manual;
    reg request_manual;
    reg [image_count-1:0] selection_mask_buf;
    reg [index_bits-1:0] search_index, active_index_buf;
    reg [index_bits:0] search_count;
    wire event_prev=prev_down || (!next_down && manual_pending && pending_prev);
    wire [image_count-1:0] effective_selection_mask = external_control ? selection_mask : {image_count{1'b1}};
    wire [image_count-1:0] selected_valid_mask = valid_mask & effective_selection_mask;
    assign timer_en = enable && auto_mode && !request_busy && !manual_pending;

    function [index_bits-1:0] step_index;
        input [index_bits-1:0] current_index;
        input prev_flag;
        begin
            step_index = prev_flag ? (current_index==0 ? image_count-1 : current_index-1'b1) :
                (current_index==image_count-1 ? 0 : current_index+1'b1);
        end
    endfunction

    function [index_bits-1:0] first_valid_index;
        input [image_count-1:0] mask;
        reg found;
        begin
            first_valid_index=0; found=0;
            for(integer i=0;i<image_count;i=i+1)
                if(mask[i] && !found) begin first_valid_index=i; found=1; end
        end
    endfunction

    function [index_bits-1:0] next_valid_index;
        input [index_bits-1:0] current_index;
        input [image_count-1:0] mask;
        input prev_flag;
        reg [index_bits-1:0] candidate;
        reg found;
        begin
            next_valid_index=current_index; candidate=current_index; found=0;
            for(integer i=0;i<image_count;i=i+1) begin
                candidate=step_index(candidate,prev_flag);
                if(mask[candidate] && !found) begin next_valid_index=candidate; found=1; end
            end
        end
    endfunction

    generate if(image_count<=4) begin: four_image_proc
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            image_index <= 0; auto_mode <= 0; request_busy <= 0;
            auto_tick <= 0; manual_pending <= 0; pending_prev <= 0;
            manual_bad_pending <= 0; bad_prev <= 0; error_code <= 0;
        end else if (!enable) begin
            image_index <= 0; auto_mode <= 0; request_busy <= 0;
            auto_tick <= 0; manual_pending <= 0; pending_prev <= 0;
            manual_bad_pending <= 0; bad_prev <= 0; error_code <= 0;
        end else begin
            if (auto_down) auto_mode <= !auto_mode;
            if (!request_busy && !manual_bad_pending && valid_mask != 0 && !valid_mask[image_index])
                image_index <= first_valid_index(valid_mask);
            if (request_busy) begin
                auto_tick <= 0;
                if(!valid_mask[image_index]) begin
                    if(auto_mode && valid_mask!=0) image_index<=next_valid_index(image_index,valid_mask,1'b0);
                    else begin
                        image_index<=active_index; request_busy<=0;
                        manual_bad_pending<=valid_mask!=0; error_code<=valid_mask!=0 ? 8'he5 : 8'he6;
                    end
                end
                if (frame_commit && active_index == image_index) request_busy <= 0;
                if (prev_down || next_down) begin
                    manual_pending <= 1; pending_prev <= prev_down;
                end
            end else if (prev_down || next_down || manual_pending) begin
                if (manual_bad_pending) begin
                    image_index <= next_valid_index(active_index, valid_mask, bad_prev);
                    if (next_valid_index(active_index, valid_mask, bad_prev) == active_index) begin
                        error_code <= 8'he6;
                        manual_bad_pending <= 0;
                    end else begin
                        error_code <= 0; request_busy <= 1; manual_bad_pending <= 0;
                    end
                    manual_pending <= 0; auto_tick <= 0;
                end else begin
                    bad_prev <= prev_down || (!next_down && manual_pending && pending_prev);
                    if (!valid_mask[step_index(active_index,
                            prev_down || (!next_down && manual_pending && pending_prev))]) begin
                        error_code <= 8'he5; manual_bad_pending <= 1;
                        manual_pending <= 0; auto_tick <= 0;
                    end else begin
                        image_index <= step_index(active_index,
                            prev_down || (!next_down && manual_pending && pending_prev));
                        error_code <= 0; request_busy <= 1;
                        manual_pending <= 0; auto_tick <= 0;
                    end
                end
            end else if (auto_down || !auto_mode) begin
                auto_tick <= 0;
            end else if (tick_1ms) begin
                if (auto_tick == auto_period_ms-1) begin
                    image_index <= next_valid_index(active_index, valid_mask, 1'b0);
                    if (next_valid_index(active_index, valid_mask, 1'b0) != active_index) begin
                        request_busy <= 1; error_code <= 0;
                    end
                    auto_tick <= 0;
                end else auto_tick <= auto_tick+1'b1;
            end
        end
    end
    end else begin: catalog_proc
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                image_index<=0;auto_mode<=0;request_busy<=0;auto_tick<=0;
                manual_pending<=0;pending_prev<=0;manual_bad_pending<=0;bad_prev<=0;error_code<=0;
                search_flag<=0;search_prev<=0;search_manual<=0;search_index<=0;search_count<=0;
                active_index_buf<=0;
                request_manual<=0;
                selection_mask_buf<=external_control ? 0 : {image_count{1'b1}};
            end else begin
                active_index_buf<=active_index;
                if(!enable) begin
                    image_index<=0;auto_mode<=0;request_busy<=0;auto_tick<=0;
                    manual_pending<=0;manual_bad_pending<=0;error_code<=0;search_flag<=0;
                    selection_mask_buf<=external_control ? 0 : {image_count{1'b1}};
                end else begin
                    if(external_control) auto_mode<=external_auto;
                    else if(auto_down) auto_mode<=!auto_mode;
                    if (selection_mask != selection_mask_buf) begin
                        selection_mask_buf<=selection_mask;
                        auto_tick<=0; manual_pending<=0; manual_bad_pending<=0;
                        search_flag<=0; search_count<=0; request_manual<=0;
                        if (selected_valid_mask == 0) begin
                            image_index<=active_index_buf; request_busy<=0; error_code<=8'he6;
                        end else if (target_valid && selected_valid_mask[target_index]) begin
                            image_index<=target_index; request_busy<=target_index!=active_index_buf; error_code<=0;
                        end else begin
                            image_index<=first_valid_index(selected_valid_mask);
                            request_busy<=first_valid_index(selected_valid_mask)!=active_index_buf; error_code<=0;
                        end
                    end else if (target_valid) begin
                        auto_tick<=0; manual_pending<=0; manual_bad_pending<=0;
                        search_flag<=0; search_count<=0; request_manual<=1;
                        if (selected_valid_mask == 0) begin
                            image_index<=active_index_buf; request_busy<=0; error_code<=8'he6;
                        end else if (selected_valid_mask[target_index]) begin
                            image_index<=target_index; request_busy<=target_index!=active_index_buf; error_code<=0;
                        end else begin
                            image_index<=first_valid_index(selected_valid_mask);
                            request_busy<=first_valid_index(selected_valid_mask)!=active_index_buf; error_code<=0;
                        end
                    end else begin
                        if(request_busy) begin
                            auto_tick<=0;
                            if(external_control && !request_manual && (prev_down || next_down) && !discard_events)begin
                                manual_pending<=0;manual_bad_pending<=0;request_manual<=1;
                                bad_prev<=prev_down;search_flag<=1;search_prev<=prev_down;
                                search_manual<=1;search_count<=0;
                                search_index<=step_index(active_index_buf,prev_down);error_code<=0;
                            end else begin
                            if((prev_down || next_down) && !(external_control && discard_events)) begin
                                manual_pending<=1;pending_prev<=prev_down;
                            end
                            if(search_flag) begin
                                if(selected_valid_mask[search_index]) begin
                                    search_flag<=0;image_index<=search_index;
                                    if(search_index==active_index_buf) begin
                                        request_busy<=0;error_code<=search_manual ? 8'he6 : 0;
                                    end else error_code<=0;
                                end else if(search_count==image_count-1) begin
                                    search_flag<=0;request_busy<=0;error_code<=8'he6;
                                end else begin
                                    search_index<=step_index(search_index,search_prev);search_count<=search_count+1'b1;
                                end
                            end else if(!selected_valid_mask[image_index]) begin
                                if(selected_valid_mask!=0) begin
                                    search_flag<=1;
                                    search_prev<=external_control ? (request_manual ? bad_prev : 1'b0) : 1'b0;
                                    search_manual<=request_manual;
                                    search_index<=step_index(image_index,
                                        external_control ? (request_manual ? bad_prev : 1'b0) : 1'b0);
                                    search_count<=0;
                                    error_code<=8'he5;
                                end else begin
                                    image_index<=active_index_buf;request_busy<=0;
                                    manual_bad_pending<=0;error_code<=8'he6;
                                end
                            end else if(frame_commit && active_index==image_index) request_busy<=0;
                            end
                        end else if((prev_down || next_down || manual_pending) &&
                                    !(external_control && discard_events)) begin
                            auto_tick<=0;manual_pending<=0;
                            request_manual<=1;
                            if(manual_bad_pending) begin
                                search_flag<=1;search_prev<=bad_prev;search_manual<=1;search_count<=0;
                                search_index<=step_index(active_index_buf,bad_prev);
                                request_busy<=1;manual_bad_pending<=0;
                            end else begin
                                bad_prev<=event_prev;
                                if(!selected_valid_mask[step_index(active_index_buf,event_prev)]) begin
                                    search_flag<=1;search_prev<=event_prev;search_manual<=1;
                                    search_count<=0;
                                    search_index<=step_index(active_index_buf,event_prev);
                                    request_busy<=1;manual_bad_pending<=0;
                                    error_code<=effective_selection_mask[step_index(active_index_buf,event_prev)] ?
                                        8'he5 : 8'd0;
                                end else begin
                                    image_index<=step_index(active_index_buf,event_prev);request_busy<=1;error_code<=0;
                                end
                            end
                        end else if(external_control ? discard_events || !external_auto : auto_down || !auto_mode)
                            auto_tick<=0;
                        else if(external_control ? auto_step : tick_1ms) begin
                            if(external_control || auto_tick==auto_period_ms-1) begin
                                search_flag<=1;search_prev<=0;search_manual<=0;search_count<=0;
                                request_manual<=0;manual_bad_pending<=0;
                                search_index<=step_index(active_index_buf,1'b0);request_busy<=1;auto_tick<=0;
                            end else auto_tick<=auto_tick+1'b1;
                        end
                        if(!request_busy && !manual_bad_pending &&
                           !(prev_down || next_down || manual_pending) &&
                           !selected_valid_mask[image_index])
                            image_index<=active_index_buf;
                        if(external_control && discard_events) begin
                            manual_pending<=0;manual_bad_pending<=0;auto_tick<=0;
                            if(search_flag) begin
                                search_flag<=0;request_busy<=0;image_index<=active_index_buf;
                            end
                        end
                    end
                end
            end
        end
    end endgenerate
endmodule
