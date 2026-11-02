module photo_audio_product #(
    parameter integer frame_pixels=307200,
    parameter integer unit_samples=4800
) (
    input wire mem_clk, input wire mem_rst_n, input wire clk, input wire rst_n,
    input wire [1:0] scene_mode, input wire menu_active, input wire music_enable,input wire source_enable,
    input wire [2:0] music_volume, input wire exam_running, input wire exam_finished,
    input wire exam_reset, input wire [31:0] remaining_seconds,
    input wire frame_sync, input wire video_de, input wire video_visible,
    input wire underflow_flag, input wire visible_valid, input wire [3:0] visible_index,
    input wire scene_visible, input wire visible_frame_pulse, input wire [7:0] reader_error,
    input wire hdmi_video_locked,
    input wire wav_ready, input wire signed [15:0] wav_sample,
    output wire sample_tick, output wire wav_consume,
    output reg audio_valid, output reg [23:0] audio_left_data,
    output wire [23:0] audio_right_data, output wire acr_valid,
    output wire [19:0] acr_cts, output wire [19:0] acr_n,
    output wire music_ready, output wire effect_active,output wire error_flag
);
    wire [6:0] config_live={scene_mode,menu_active,music_enable,music_volume};
    reg [6:0] config_hold,config_active;
    reg config_req,config_ack,config_sent;
    (* async_reg="true" *) reg [1:0] config_req_sync,config_ack_sync,event_sync,event_ack_sync;
    wire event_req,event_error; wire [2:0] event_code;
    (* async_reg="true" *) reg [1:0] enable_sync,error_sync;
    (* async_reg="true" *) reg [1:0] hdmi_lock_sync,reader_fault_sync;
    assign error_flag=error_sync[1];
    reg event_ack;
    photo_audio_events events_proc(.clk(mem_clk),.rst_n(mem_rst_n),.scene_mode(scene_mode),
        .running(exam_running),.finished(exam_finished),.reset_cmd(exam_reset),
        .remaining_seconds(remaining_seconds),.event_ack(event_ack_sync[1]),
        .event_request(event_req),.event_code(event_code),.error_flag(event_error));
    always @(posedge mem_clk or negedge mem_rst_n)begin
        if(!mem_rst_n)begin config_hold<=0;config_req<=0;config_sent<=0;config_ack_sync<=0;event_ack_sync<=0;end
        else begin
            config_ack_sync<={config_ack_sync[0],config_ack};event_ack_sync<={event_ack_sync[0],event_ack};
            if(config_req==config_ack_sync[1] && (!config_sent || config_hold!=config_live))begin
                config_hold<=config_live;config_req<=!config_req;config_sent<=1;
            end
        end
    end
    wire [1:0] scene=config_active[6:5];
    wire ordinary=scene==0;
    reg [11:0] rate;
    assign sample_tick=rate>=3119;
    reg [19:0] phase;
    reg [3:0] effect;
    reg [3:0] step;
    localparam integer count_bits=$clog2(unit_samples+unit_samples/2+1);
    reg [count_bits-1:0] effect_count;
    reg startup_started, startup_done;
    wire [count_bits-1:0] effect_limit=(effect==1 && step==1) ? unit_samples+unit_samples/2-1 : unit_samples-1;
    reg qualified;
    reg [3:0] previous_index;
    reg previous_valid,menu_old;
    reg visible_frame_seen, fire_visible_latched;
    reg [1:0] scene_previous;
    wire valid_pixel=video_de && video_visible && !underflow_flag && visible_valid;
    wire startup_playing=startup_started;
    assign music_ready=qualified;
    assign wav_consume=ordinary && visible_valid && visible_index<8 && qualified &&
        enable_sync[1] && !reader_fault_sync[1] && !error_flag && startup_done && sample_tick;
    assign effect_active=effect!=0 || (scene==2 && fire_visible_latched);
    wire [1:0] page_group=visible_index==0 ? 2 : visible_index<=3 ? 0 : visible_index<=7 ? 1 : 3;
    wire [1:0] previous_group=previous_index==0 ? 2 : previous_index<=3 ? 0 : previous_index<=7 ? 1 : 3;
    reg [19:0] phase_inc;
    reg sound_on;
    always @* begin
        phase_inc=20'd21845;sound_on=effect!=0;
        case(effect)
            1:phase_inc=step==0 ? 20'd13107 : 20'd21845;
            2:phase_inc=20'd10923;
            3:phase_inc=20'd26214;
            4:begin phase_inc=20'd21845;sound_on=!step[0];end
            5:phase_inc=20'd26214;
            6:begin phase_inc=20'd17476;sound_on=!step[0];end
            7:phase_inc=20'd32768;
            8:phase_inc=20'd21845;
            default:sound_on=0;
        endcase
        if(scene==2)begin phase_inc=step<5 ? 20'd17476 : 20'd26214;sound_on=1;end
    end
    function signed [15:0] sine_sample;
        input [5:0] index; reg [4:0] pos; reg signed [15:0] magnitude;
        begin
            pos=index[4] ? 5'd16-{1'b0,index[3:0]} : {1'b0,index[3:0]};
            case(pos)
                0:magnitude=0;1:magnitude=1176;2:magnitude=2341;3:magnitude=3483;
                4:magnitude=4592;5:magnitude=5657;6:magnitude=6667;7:magnitude=7613;
                8:magnitude=8485;9:magnitude=9276;10:magnitude=9978;11:magnitude=10583;
                12:magnitude=11087;13:magnitude=11483;14:magnitude=11769;15:magnitude=11942;
                default:magnitude=12000;
            endcase
            sine_sample=index[5] ? -magnitude : magnitude;
        end
    endfunction
    function signed [15:0] volume_proc;
        input signed [15:0] value;input [2:0] level;reg signed [17:0] expanded;
        begin expanded={{2{value[15]}},value};
            case(level)0:volume_proc=0;1:volume_proc=expanded>>>2;2:volume_proc=expanded>>>1;
                3:volume_proc=(expanded+(expanded<<<1))>>>2;default:volume_proc=value;endcase
        end
    endfunction
    wire signed [15:0] tone=sine_sample(phase[19:14]);
    wire signed [15:0] ordinary_tone=volume_proc((tone+(tone>>>1))>>>1,config_active[2:0]);
    wire signed [15:0] music=volume_proc(wav_sample,config_active[2:0]);
    assign audio_right_data=audio_left_data;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            config_req_sync<=0;config_ack<=0;config_active<=0;event_sync<=0;event_ack<=0;
            enable_sync<=0;error_sync<=0;hdmi_lock_sync<=0;reader_fault_sync<=0;
            rate<=0;phase<=0;effect<=7;step<=0;effect_count<=0;startup_started<=0;startup_done<=0;
            qualified<=0;
            previous_index<=0;previous_valid<=0;menu_old<=0;
            visible_frame_seen<=0;fire_visible_latched<=0;scene_previous<=0;
            audio_valid<=0;audio_left_data<=0;
        end else begin
            config_req_sync<={config_req_sync[0],config_req};event_sync<={event_sync[0],event_req};
            enable_sync<={enable_sync[0],source_enable};error_sync<={error_sync[0],event_error};
            hdmi_lock_sync<={hdmi_lock_sync[0],hdmi_video_locked};
            reader_fault_sync<={reader_fault_sync[0],reader_error!=0};
            if(config_req_sync[1]!=config_ack)begin
                config_active<=config_hold;config_ack<=config_req_sync[1];
                if(config_hold[6:5]!=config_active[6:5] && effect!=7)begin effect<=0;step<=0;effect_count<=0;end
            end
            menu_old<=config_active[4];scene_previous<=scene;
            if(!startup_started && visible_frame_seen && ordinary && enable_sync[1])
                startup_started<=1;
            if(visible_frame_pulse && ordinary && visible_valid && visible_index<8)
                visible_frame_seen<=1;
            if(!enable_sync[1] || reader_fault_sync[1])begin
                qualified<=0;visible_frame_seen<=0;
            end else if(!qualified && startup_done && visible_frame_seen && wav_ready && ordinary)
                qualified<=1;
            if(scene!=scene_previous)begin
                if(scene!=0)begin qualified<=0;visible_frame_seen<=0;end
                if(scene==2)begin fire_visible_latched<=0;phase<=0;step<=0;effect_count<=0;end
                else fire_visible_latched<=0;
            end
            if(scene==2 && scene_visible && visible_index==9 && valid_pixel)fire_visible_latched<=1;
            rate<=sample_tick ? rate-12'd3119 : rate+12'd6;
            audio_valid<=sample_tick;
            if(sample_tick)begin
                if((effect==7 && !startup_playing) || (scene==2 && !fire_visible_latched))phase<=0;
                else phase<=phase+phase_inc;
                audio_left_data<=0;
                if(!error_flag && ((scene==2 && fire_visible_latched) || (effect!=0 && effect!=8)))begin
                    if(sound_on && (effect!=7 || startup_playing))audio_left_data<={tone,8'd0};
                end else if(!error_flag && ordinary && config_active[3])begin
                    if(effect==8)audio_left_data<={ordinary_tone,8'd0};
                    else if(wav_consume && wav_ready)audio_left_data<={music,8'd0};
                end
                if(effect!=0 || scene==2)begin
                    if((effect==7 && !startup_playing) || (scene==2 && !fire_visible_latched))begin
                        effect_count<=0;
                    end else if(effect_count==effect_limit)begin
                        effect_count<=0;
                        if(scene==2)step<=step==9 ? 0 : step+1'b1;
                        else if((effect==1 && step==1) || (effect==4 && step==2) ||
                            (effect==6 && step==4) || (effect!=1 && effect!=4 && effect!=6))begin
                            effect<=0;step<=0;if(effect==7)startup_done<=1;
                        end else step<=step+1'b1;
                    end else effect_count<=effect_count+1'b1;
                end
            end
            if(valid_pixel && (!previous_valid || previous_index!=visible_index))begin
                if(previous_valid && ordinary && previous_group<3 && page_group<3 && page_group!=previous_group && startup_done)begin
                    effect<=8;step<=0;effect_count<=0;
                end
                previous_valid<=1;previous_index<=visible_index;
            end
            if(ordinary && config_active[4] && !menu_old && startup_done)begin effect<=8;step<=0;effect_count<=0;end
            if(event_sync[1]!=event_ack)begin
                event_ack<=event_sync[1];
                if(event_code==0)begin if(effect!=7)begin effect<=0;step<=0;effect_count<=0;end end
                else if(scene==1)begin effect<={1'b0,event_code};step<=0;effect_count<=0;startup_done<=1;end
            end
            if(scene==2)begin effect<=0;startup_done<=1;end
            else if(!ordinary && effect==8)effect<=0;
        end
    end
    audio_arc_calculate #(.ACR_N(6144)) acr_proc(.I_clk(clk),.I_rst(!rst_n),.I_audio_valid(audio_valid),
        .O_acr_valid(acr_valid),.O_acr_cts(acr_cts),.O_acr_n(acr_n));
endmodule
