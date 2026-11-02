`timescale 1ns/1ps
module photo_transition_control (
    input wire mem_clk, input wire mem_rst_n,
    input wire allow_transition, input wire [1:0] transition_mode,
    input wire display_ready, input wire [3:0] requested_index,
    input wire [3:0] display_index, input wire target_ready,
    output wire display_publish_enable, output wire transition_busy,
    input wire pix_clk, input wire pix_rst_n, input wire frame_start,
    input wire incoming_valid, input wire [3:0] incoming_index,
    input wire visible_valid, input wire [3:0] visible_index,
    output wire [7:0] background_alpha,
    output wire wipe_active, output wire [4:0] wipe_ramp
);
    localparam [2:0] pix_idle=0, pix_fade_out=1, pix_black=2,
        pix_fade_in=3, pix_wipe_wait=4, pix_wipe=5;
    localparam [4:0] transition_frames=5'd16;
    reg transaction_active, cancel_request, request_toggle;
    reg [1:0] mode_hold;
    reg [3:0] index_hold;
    reg accepted_toggle, done_toggle, black_ready;
    (* async_reg = "true" *) reg [1:0] accepted_sync, done_sync, black_sync;
    (* async_reg = "true" *) reg [1:0] request_sync, allow_sync, cancel_sync;
    reg [2:0] pixel_state;
    reg [4:0] pixel_ramp;
    reg [3:0] pixel_target;
    wire different_target=display_ready && requested_index!=display_index;
    wire incoming_target=incoming_valid && incoming_index==pixel_target;
    wire visible_target=visible_valid && visible_index==pixel_target;
    wire command_idle=done_sync[1]==request_toggle;

    assign transition_busy=allow_transition &&
        (transaction_active || (transition_mode!=0 && different_target));
    assign display_publish_enable=!allow_transition || !display_ready ? 1'b1 :
        transaction_active ? (requested_index==index_hold &&
            (mode_hold==2 ? accepted_sync[1]==request_toggle : black_sync[1])) :
        !(transition_mode!=0 && different_target);
    assign background_alpha=(pixel_state==pix_fade_out || pixel_state==pix_black ||
        pixel_state==pix_fade_in) && pixel_ramp!=transition_frames ?
        {pixel_ramp[3:0],4'b0} : 8'hff;
    assign wipe_active=pixel_state==pix_wipe || (pixel_state==pix_wipe_wait && incoming_target);
    assign wipe_ramp=pixel_ramp;

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if(!mem_rst_n) begin
            transaction_active<=0;cancel_request<=0;request_toggle<=0;
            mode_hold<=0;index_hold<=0;accepted_sync<=0;done_sync<=0;black_sync<=0;
        end else begin
            accepted_sync<={accepted_sync[0],accepted_toggle};
            done_sync<={done_sync[0],done_toggle};
            black_sync<={black_sync[0],black_ready};
            if(transaction_active) begin
                if(!allow_transition || !display_ready || requested_index!=index_hold) begin
                    transaction_active<=0;cancel_request<=1;
                end else if(command_idle) transaction_active<=0;
            end else if(cancel_request) begin
                if(command_idle) cancel_request<=0;
            end else if(allow_transition && different_target && target_ready &&
                        transition_mode!=0 && transition_mode<=2 && command_idle) begin
                mode_hold<=transition_mode;index_hold<=requested_index;
                request_toggle<=~request_toggle;transaction_active<=1;
            end
        end
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if(!pix_rst_n) begin
            request_sync<=0;allow_sync<=0;cancel_sync<=0;
            accepted_toggle<=0;done_toggle<=0;black_ready<=0;
            pixel_state<=pix_idle;pixel_ramp<=transition_frames;pixel_target<=0;
        end else begin
            request_sync<={request_sync[0],request_toggle};
            allow_sync<={allow_sync[0],allow_transition};
            cancel_sync<={cancel_sync[0],cancel_request};
            if(!allow_sync[1] || (cancel_sync[1] && (frame_start || pixel_state==pix_idle))) begin
                pixel_state<=pix_idle;pixel_ramp<=transition_frames;black_ready<=0;
                accepted_toggle<=request_sync[1];done_toggle<=request_sync[1];
            end else if(!cancel_sync[1] && request_sync[1]!=accepted_toggle) begin
                accepted_toggle<=request_sync[1];pixel_target<=index_hold;black_ready<=0;
                pixel_state<=mode_hold==1 ? pix_fade_out : pix_wipe_wait;
                pixel_ramp<=mode_hold==1 ? transition_frames : 5'd0;
            end else if(pixel_state==pix_wipe_wait && incoming_target) begin
                pixel_state<=pix_wipe;
            end else if(frame_start) begin
                case(pixel_state)
                    pix_fade_out: if(pixel_ramp>1) pixel_ramp<=pixel_ramp-1'b1;
                        else begin pixel_state<=pix_black;pixel_ramp<=0;black_ready<=1;end
                    pix_black: if(visible_target) begin
                        pixel_state<=pix_fade_in;pixel_ramp<=1;black_ready<=0;
                    end
                    pix_fade_in,pix_wipe: if(pixel_state==pix_fade_in || visible_target) begin
                        if(pixel_ramp<transition_frames-1'b1) pixel_ramp<=pixel_ramp+1'b1;
                        else begin
                            pixel_state<=pix_idle;pixel_ramp<=transition_frames;done_toggle<=accepted_toggle;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
