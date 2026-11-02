module photo_sector_arbiter (
    input wire clk,input wire rst_n,input wire audio_urgent,
    input wire image_req,input wire [31:0] image_lba,
    input wire audio_req,input wire [31:0] audio_lba,
    output wire client_busy,output reg card_req,output reg [31:0] card_lba,
    input wire card_busy,input wire card_done,
    output wire image_owner,output wire audio_owner
);
    reg image_pending,audio_pending;
    reg [31:0] image_hold,audio_hold;
    reg [1:0] owner;
    assign image_owner=owner==1;
    assign audio_owner=owner==2;
    assign client_busy=card_busy || owner!=0 || image_pending || audio_pending || card_req;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin image_pending<=0;audio_pending<=0;image_hold<=0;audio_hold<=0;owner<=0;card_req<=0;card_lba<=0;end
        else begin
            if(card_busy || card_done)card_req<=0;
            if(image_req)begin image_pending<=1;image_hold<=image_lba;end
            if(audio_req)begin audio_pending<=1;audio_hold<=audio_lba;end
            if(owner!=0)begin if(card_done)owner<=0;end
            else if(!card_busy && !card_req)begin
                if(audio_pending && (audio_urgent || !image_pending))begin
                    owner<=2;card_lba<=audio_hold;card_req<=1;audio_pending<=0;
                end else if(image_pending)begin owner<=1;card_lba<=image_hold;card_req<=1;image_pending<=0;end
            end
        end
    end
endmodule
