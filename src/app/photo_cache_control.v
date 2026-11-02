`timescale 1ns/1ps
module photo_cache_control #(
    parameter integer group_prefetch=0
) (
    input wire clk, input wire rst_n, input wire catalog_ready,
    input wire [9:0] valid_mask, input wire [3:0] requested_index, input wire auto_mode,
    input wire display_publish_enable,
    input wire [9:0] selection_mask,
    input wire [11:0] load_source_width, input wire [11:0] load_source_height,
    input wire [1:0] active_bank,
    input wire file_done, input wire file_cancelled, input wire [3:0] bank_complete,
    output reg file_request, output wire file_cancel, output reg [3:0] file_index,
    output reg [1:0] load_bank,
    output reg display_ready, output reg [1:0] display_bank,
    output wire [3:0] display_index, output wire [3:0] active_index,
    output wire [11:0] active_source_width, output wire [11:0] active_source_height,
    output reg [3:0] cache_valid, output wire target_ready
);
    localparam [2:0] st_idle=0, st_first=1, st_lookup=2, st_next=3,
        st_choose=4, st_accept=5, st_load=6, st_sleep=7;
    reg [2:0] state;
    reg [1:0] replace_index, scan_slot, slot_attempt;
    reg [3:0] cache_index [0:3];
    reg [11:0] cache_source_width [0:3], cache_source_height [0:3];
    reg [3:0] target_index, search_count, saved_request, published_index;
    reg [9:0] saved_mask, saved_selection;
    reg prefetch, second_ahead, saved_auto, previous_valid;
    reg [1:0] ahead_bank, previous_bank, active_bank_buf;
    wire [3:0] request_slots;
    wire request_hit=|request_slots;
    wire [1:0] request_bank=request_slots[0] ? 2'd0 : request_slots[1] ? 2'd1 :
        request_slots[2] ? 2'd2 : 2'd3;
    wire [9:0] prefetch_mask=group_prefetch ? valid_mask & selection_mask : valid_mask;
    wire plan_changed=requested_index!=saved_request || valid_mask!=saved_mask || auto_mode!=saved_auto ||
        (group_prefetch && selection_mask!=saved_selection);
    generate for(genvar i=0;i<4;i=i+1) begin: request_hit_proc
        assign request_slots[i]=cache_valid[i] && cache_index[i]==requested_index &&
            requested_index<10 && valid_mask[requested_index];
    end endgenerate
    assign display_index=published_index;
    assign active_index=cache_index[active_bank];
    assign active_source_width=cache_source_width[active_bank];
    assign active_source_height=cache_source_height[active_bank];
    assign target_ready=request_hit;
    assign file_cancel=group_prefetch && display_ready && state==st_load && !request_hit &&
        requested_index<10 && valid_mask[requested_index] && requested_index!=file_index;
    function [3:0] step_index;
        input [3:0] index;
        begin step_index=index==9 ? 0 : index+1'b1; end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=st_idle;replace_index<=0;cache_valid<=0;
            scan_slot<=0;slot_attempt<=0;target_index<=0;search_count<=0;
            saved_request<=0;saved_mask<=0;saved_selection<=0;prefetch<=0;second_ahead<=0;saved_auto<=0;
            ahead_bank<=0;previous_bank<=0;previous_valid<=0;active_bank_buf<=0;
            file_request<=0;file_index<=0;load_bank<=0;
            display_ready<=0;display_bank<=0;published_index<=0;
            for(integer i=0;i<4;i=i+1) begin
                cache_index[i]<=0;cache_source_width[i]<=0;cache_source_height[i]<=0;
            end
        end else begin
            file_request<=0;
            active_bank_buf<=active_bank;
            if(display_ready && active_bank!=active_bank_buf) begin
                previous_bank<=active_bank_buf;previous_valid<=cache_valid[active_bank_buf];
            end
            if(state!=st_idle && state!=st_accept && state!=st_load && plan_changed) state<=st_idle;
            else case(state)
                st_idle: begin
                    slot_attempt<=0;
                    if(catalog_ready && valid_mask!=0) begin
                    saved_request<=requested_index;saved_mask<=valid_mask;saved_auto<=auto_mode;
                    saved_selection<=selection_mask;
                    prefetch<=0;second_ahead<=0;scan_slot<=0;
                    if(!display_ready) begin
                        target_index<=requested_index<10 ? requested_index : 0;
                        state<=st_first;
                    end
                    else begin
                        target_index<=requested_index<10 && valid_mask[requested_index] ?
                            requested_index : display_index;
                        state<=st_lookup;
                    end
                    end
                end
                st_first: if(valid_mask[target_index]) state<=st_lookup;
                    else if(target_index==9) state<=st_sleep;
                    else target_index<=target_index+1'b1;
                st_lookup: begin
                    if(cache_valid[scan_slot] && cache_index[scan_slot]==target_index) begin
                        if(prefetch) begin
                            if(group_prefetch) begin
                                target_index<=step_index(target_index);search_count<=0;state<=st_next;
                            end else if(auto_mode || second_ahead) state<=st_sleep;
                            else begin
                                ahead_bank<=scan_slot;second_ahead<=1;
                                target_index<=step_index(target_index);search_count<=0;state<=st_next;
                            end
                        end
                        else if(display_publish_enable || group_prefetch) begin
                            if(display_publish_enable) begin
                                display_bank<=scan_slot;display_ready<=1;published_index<=target_index;
                            end
                            target_index<=step_index(target_index);search_count<=0;state<=st_next;
                        end
                    end else if(scan_slot==3) begin slot_attempt<=0;state<=st_choose; end
                    else scan_slot<=scan_slot+1'b1;
                end
                st_next: if(target_index==(group_prefetch && requested_index<10 && valid_mask[requested_index] ?
                    requested_index : display_index)) state<=st_sleep;
                else if(prefetch_mask[target_index]) begin
                    prefetch<=1;scan_slot<=0;state<=st_lookup;
                end else if(search_count==9) state<=st_sleep;
                else begin target_index<=step_index(target_index);search_count<=search_count+1'b1; end
                st_choose: begin
                    if(!display_ready || (replace_index!=active_bank && replace_index!=display_bank &&
                        !request_slots[replace_index] &&
                        (active_bank==active_bank_buf || replace_index!=active_bank_buf) &&
                        (group_prefetch ? !(prefetch && cache_valid[replace_index] && prefetch_mask[cache_index[replace_index]]) :
                            ((!previous_valid || replace_index!=previous_bank) &&
                             (!second_ahead || replace_index!=ahead_bank))))) begin
                        load_bank<=replace_index;cache_valid[replace_index]<=0;
                        file_index<=target_index;file_request<=1;state<=st_accept;
                    end else if(slot_attempt==3) state<=st_idle;
                    else begin replace_index<=replace_index+1'b1;slot_attempt<=slot_attempt+1'b1; end
                end
                st_accept: state<=st_load;
                st_load: if(file_done) begin
                    if(!file_cancelled && valid_mask[file_index] && bank_complete[load_bank]) begin
                        cache_valid[load_bank]<=1;cache_index[load_bank]<=file_index;
                        cache_source_width[load_bank]<=load_source_width;
                        cache_source_height[load_bank]<=load_source_height;
                    end
                    replace_index<=load_bank+1'b1;state<=st_idle;
                end
                st_sleep: ;
                default: state<=st_idle;
            endcase
            if(display_ready && request_hit && display_publish_enable) begin
                display_bank<=request_bank;published_index<=requested_index;
            end
        end
    end
endmodule
