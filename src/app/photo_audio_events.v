module photo_audio_events (
    input wire clk, input wire rst_n,
    input wire [1:0] scene_mode, input wire running, input wire finished,
    input wire reset_cmd, input wire [31:0] remaining_seconds,
    input wire event_ack, output reg event_request, output reg [2:0] event_code,output reg error_flag
);
    reg running_old, finished_old, started;
    reg [31:0] seconds_old;
    reg [1:0] scene_old;
    reg [2:0] next_event;
    always @* begin
        next_event=0;
        if(scene_mode==1 && scene_old==1 && !reset_cmd)begin
            if(finished && !finished_old)next_event=6;
            else if(running && !running_old)next_event=started ? 3 : 1;
            else if(!running && running_old && !finished)next_event=2;
            else if(running && seconds_old==61 && remaining_seconds==60)next_event=4;
            else if(running && seconds_old==11 && remaining_seconds==10)next_event=5;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            running_old<=0;finished_old<=0;started<=0;seconds_old<=0;scene_old<=0;
            event_request<=0;event_code<=0;error_flag<=0;
        end else begin
            running_old<=running;finished_old<=finished;seconds_old<=remaining_seconds;scene_old<=scene_mode;
            if(scene_mode==0 || reset_cmd)started<=0;
            else if(scene_mode==1 && running)started<=1;
            if((next_event!=0 || reset_cmd || scene_mode!=scene_old) && event_request==event_ack)begin
                event_code<=next_event;event_request<=!event_request;
            end
            if(next_event!=0 && event_request!=event_ack)error_flag<=1;
        end
    end
endmodule
