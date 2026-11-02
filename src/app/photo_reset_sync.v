module photo_reset_sync (
    input wire clk, input wire reset_req, output wire rst_n
);
    reg [3:0] reset_buf;
    always @(posedge clk or posedge reset_req) begin
        if (reset_req) reset_buf <= 4'hf;
        else reset_buf <= {reset_buf[2:0],1'b0};
    end
    assign rst_n = !reset_buf[3];
endmodule
