`timescale 1ns/1ps
module tb_photo_wav_errors;
    reg clk=0,pix_clk=0,rst_n=0;
    always #4 clk=~clk;always #20 pix_clk=~pix_clk;
    reg start=0,valid=0,ending=0,available=1,catalog=0;
    reg [7:0] data=0;
    reg [31:0] offset=0,size=10056;
    reg [7:0] corpus[0:10055];
    wire [7:0] error_code;wire ready,done;
    integer result_file;
    photo_wav_stream dut(.clk(clk),.rst_n(rst_n),.play_enable(1'b1),.catalog_ready(catalog),
        .fs_busy(1'b1),.fs_done(1'b0),.fs_error(8'd0),.available(available),.file_request(),.file_pause(),
        .load_done(done),.load_error(),.file_start(start),.file_size(size),.file_valid(valid),
        .file_data(data),.file_offset(offset),.file_end(ending),.pix_clk(pix_clk),.pix_rst_n(rst_n),.consume(1'b0),
        .sample_data(),.sample_ready(ready),.urgent(),.error_code(error_code),.samples_written(),.underflows());
    task run_case(input integer mode,input [7:0] expected);
        integer i,count;reg [7:0] value;
        begin
            rst_n=0;start=0;valid=0;ending=0;repeat(10)@(negedge clk);rst_n=1;
            @(negedge clk);start=1;@(negedge clk);start=0;
            count=mode==7 ? 100 : 60;
            for(i=0;i<count;i=i+1)begin
                value=corpus[i];
                case(mode)
                    1:if(i==0)value="X";
                    2:if(i==34)value=2;  
                    3:if(i==32)value=3;  
                    4:if(i==36)value=8'h44;  
                    5:if(i==52)value=8'h11;  
                    6:if(i==55)value=8'h7f;  
                endcase
                @(negedge clk);valid=1;data=value;offset=i;
            end
            @(negedge clk);valid=0;ending=1;@(negedge clk);ending=0;
            repeat(30)@(negedge clk);
            if(error_code!==expected || ready)$fatal(1,"malformed WAV case=%d code=%h expected=%h ready=%b",mode,error_code,expected,ready);
        end
    endtask
    initial begin
        result_file=$fopen("tb_photo_wav_errors.result","w");$readmemh("work/wav_fixture.hex",corpus);
        run_case(1,8'h91);run_case(2,8'h92);run_case(3,8'h92);run_case(4,8'h92);
        run_case(5,8'h92);run_case(6,8'h91);run_case(7,8'h91);
        $fdisplay(result_file,"PASS corrupt RIFF, stereo/float/rate rejection, odd data, overflowing chunk, truncated payload stay silent");
        $fdisplay(result_file,"PASS tb_photo_wav_errors");$fclose(result_file);$finish;
    end
endmodule
