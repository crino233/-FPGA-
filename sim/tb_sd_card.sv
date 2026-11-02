`timescale 1ns/1ps
module sd_card_model #(
    parameter integer retain_read=0,
    parameter integer zero_data=0,
    parameter integer volume_mode=0
) (
    input wire cs_n,input wire sclk,input wire mosi,
    input wire low_capacity,input wire corrupt_crc,input wire absent_flag,
    input wire [7:0] reset_r1,input wire reset_silent,input wire bad_echo,input wire init_stall,
    output reg miso=1,output reg cmd16_seen=0
);
    reg [7:0] rx_buf=0;
    reg [47:0] command_buf=0;
    reg [7:0] response_buf [0:519];
    integer rx_bit=0,cmd_pos=0,tx_pos=0,tx_bit=0,tx_length=0;
    integer acmd_count=0,i,index;
    integer cmd0_count=0,cmd8_count=0,token_delay_left=0;
    reg read_pending=0;
    reg [7:0] rx_byte;
    reg [31:0] arg;
    reg [15:0] volume_crc;
    function automatic [7:0] volume_byte(input integer lba,input integer pos);
        begin
            volume_byte=0;
            if(lba==0)case(pos)
                12:volume_byte=2;13:volume_byte=1;14:volume_byte=32;16:volume_byte=2;
                32,33,34,35:volume_byte=131072>>((pos-32)*8);
                37:volume_byte=4;44:volume_byte=2;510:volume_byte=8'h55;511:volume_byte=8'haa;
            endcase
            else if(lba==32)begin
                if(pos/4==10)volume_byte=11>>((pos%4)*8);
                else volume_byte=32'h0fffffff>>((pos%4)*8);
            end else if(lba==2080)case(pos)
                0,1,2,3,4,5,6,7,8,9,10:volume_byte=88'h5049433220202020424d50>>(80-pos*8);
                11:volume_byte=8'h20;26:volume_byte=10;
                28,29,30,31:volume_byte=822>>((pos-28)*8);
            endcase
            else if(lba==2088 || lba==2089)begin
                case((lba-2088)*512+pos)
                    0:volume_byte="B";1:volume_byte="M";2:volume_byte=8'h36;3:volume_byte=3;
                    10:volume_byte=54;14:volume_byte=40;18:volume_byte=32;22:volume_byte=8;
                    26:volume_byte=1;28:volume_byte=24;
                    default:volume_byte=(lba-2088)*512+pos>=54 ? pos : 0;
                endcase
            end
        end
    endfunction
    function automatic [15:0] volume_crc_next(input [15:0] crc,input [7:0] value);
        reg [15:0] c;
        begin c=crc^{value,8'd0};for(integer bit_pos=0;bit_pos<8;bit_pos=bit_pos+1)c=c[15] ? (c<<1)^16'h1021 : c<<1;volume_crc_next=c;end
    endfunction
    always @(posedge cs_n) begin
        rx_bit=0; cmd_pos=0; rx_buf=0;
    end
    always @(posedge sclk) if(!cs_n && !absent_flag) begin
        rx_byte={rx_buf[6:0],mosi}; rx_buf=rx_byte;
        if(rx_bit==7) begin
            rx_bit=0;
            if(cmd_pos==0) begin
                if(rx_byte[7:6]==2'b01) begin command_buf=rx_byte; cmd_pos=1; end
            end else if(cmd_pos<5) begin
                command_buf={command_buf[39:0],rx_byte}; cmd_pos=cmd_pos+1;
            end else begin
                index=command_buf[37:32]; arg=command_buf[31:0];
                cmd_pos=0;
                if(!(retain_read && read_pending)) begin
                tx_pos=0; tx_bit=0;
                case(index)
                    0: begin
                        if(rx_byte!=8'h95 || arg!=0) $fatal(1,"CMD0 packet");
                        response_buf[0]=reset_r1; tx_length=reset_silent ? 0 : 1;
                        acmd_count=0; cmd16_seen=0;cmd0_count=cmd0_count+1;
                    end
                    8: begin
                        if(rx_byte!=8'h87 || arg!=32'h1aa) $fatal(1,"CMD8 packet");
                        response_buf[0]=1; response_buf[1]=0; response_buf[2]=0;
                        response_buf[3]=1; response_buf[4]=bad_echo ? 8'hab : 8'haa;
                        tx_length=5;cmd8_count=cmd8_count+1;
                    end
                    55: begin response_buf[0]=1; tx_length=1; end
                    41: begin
                        if(arg!=32'h40000000) $fatal(1,"ACMD41 argument");
                        response_buf[0]=acmd_count==0 || init_stall ? 1 : 0;
                        acmd_count=acmd_count+1; tx_length=1;
                    end
                    58: begin
                        response_buf[0]=0; response_buf[1]=low_capacity ? 8'h80 : 8'hc0;
                        response_buf[2]=8'hff; response_buf[3]=8'h80; response_buf[4]=0; tx_length=5;
                    end
                    16: begin
                        if(arg!=512) $fatal(1,"CMD16 block size");
                        cmd16_seen=1; response_buf[0]=0; tx_length=1;
                    end
                    17: begin
                        if(!volume_mode && arg!=(low_capacity ? 1536 : 3)) $fatal(1,"CMD17 address=%0d",arg);
                        response_buf[0]=0; response_buf[1]=8'hff; response_buf[2]=8'hfe;
                        for(i=0;i<512;i=i+1) response_buf[i+3]=zero_data ? 0 : i;
                        response_buf[515]=zero_data ? 0 : 8'h40;
                        response_buf[516]=(zero_data ? 0 : 8'hda) ^ (corrupt_crc ? 1 : 0);
                        if(volume_mode)begin
                            volume_crc=0;
                            for(i=0;i<512;i=i+1)begin
                                response_buf[i+3]=volume_byte(low_capacity ? arg>>9 : arg,i);
                                volume_crc=volume_crc_next(volume_crc,response_buf[i+3]);
                            end
                            response_buf[515]=volume_crc[15:8];response_buf[516]=volume_crc[7:0]^(corrupt_crc ? 1 : 0);
                        end
                        tx_length=517;read_pending=retain_read;
                    end
                    default: $fatal(1,"unexpected command %0d",index);
                endcase
                end
            end
        end else rx_bit=rx_bit+1;
    end
    always @(negedge sclk or posedge cs_n) begin
        if(cs_n) begin
            miso=1;
            if(!(retain_read && read_pending)) begin tx_pos=0; tx_bit=0; tx_length=0; end
        end
        else if(retain_read && read_pending && tx_pos==1 && token_delay_left>0) begin
            miso=1;token_delay_left=token_delay_left-1;
        end
        else if(!absent_flag && tx_pos<tx_length) begin
            miso=response_buf[tx_pos][7-tx_bit];
            if(tx_bit==7) begin tx_bit=0; tx_pos=tx_pos+1; end
            else tx_bit=tx_bit+1;
            if(tx_pos==tx_length) read_pending=0;
        end else miso=1;
    end
endmodule
module tb_sd_card;
    integer result_file;
    initial result_file=$fopen("tb_sd_card.result","w");
    reg clk=0,rst_n=0,init_start=0,sector_req=0;
    reg low_capacity=0,corrupt_crc=0,absent_flag=0;
    always #4 clk=~clk;
    wire init_done,card_ready,high_capacity,sector_busy,sector_valid,sector_done;
    wire [7:0] error_code,sector_data;
    wire [8:0] sector_index;
    wire cs_n,sclk,mosi,miso,cmd16_seen;
    integer received_count=0;
    time rising_time=0;
    sd_card_reader dut (
        .clk(clk),.rst_n(rst_n),.init_start(init_start),.init_done(init_done),
        .card_ready(card_ready),.high_capacity(high_capacity),.error_code(error_code),
        .sector_req(sector_req),.sector_lba(32'd3),.sector_busy(sector_busy),
        .sector_valid(sector_valid),.sector_data(sector_data),.sector_index(sector_index),
        .sector_done(sector_done),.sd_cs_n(cs_n),.sd_sclk(sclk),.sd_mosi(mosi),.sd_miso(miso)
    );
    sd_card_model card (.cs_n(cs_n),.sclk(sclk),.mosi(mosi),.miso(miso),
        .low_capacity(low_capacity),.corrupt_crc(corrupt_crc),.absent_flag(absent_flag),.cmd16_seen(cmd16_seen),
        .reset_r1(8'h01),.reset_silent(1'b0),.bad_echo(1'b0),.init_stall(1'b0));
    always @(posedge sclk) rising_time=$time;
    always @(negedge sclk) if(rst_n && !dut.byte_abort) begin
        if($time-rising_time != (card_ready ? 32 : 1600))
            $fatal(1,"SPI half-period=%0t ready=%b",$time-rising_time,card_ready);
    end
    always @(posedge clk) if(sector_valid) begin
        if(sector_index!=received_count || sector_data!==8'(received_count))
            $fatal(1,"sector byte order index=%0d count=%0d data=%h",sector_index,received_count,sector_data);
        received_count=received_count+1;
    end
    task automatic initialize_card;
        begin
            @(negedge clk); rst_n=0; init_start=0;
            repeat(8) @(negedge clk); rst_n=1;
            repeat(4) @(negedge clk); init_start=1;
            @(negedge clk); init_start=0; wait(init_done); @(negedge clk);
        end
    endtask
    task automatic read_sector;
        begin
            received_count=0;
            @(negedge clk); sector_req=1;
            @(negedge clk); sector_req=0;
            wait(sector_done); @(negedge clk);
        end
    endtask
    initial begin
        initialize_card();
        if(error_code!=0 || !card_ready || !high_capacity) $fatal(1,"SDHC init %h",error_code);
        read_sector();
        if(error_code!=0 || received_count!=512) $fatal(1,"SDHC read %h count=%0d",error_code,received_count);
        $fdisplay(result_file,"PASS SDHC SPI initialization, divider and CRC-checked sector replay");
        corrupt_crc=1; read_sector();
        if(error_code!=8'h15 || received_count!=0) $fatal(1,"bad CRC leaked data");
        corrupt_crc=0; read_sector();
        if(error_code!=0 || received_count!=512) $fatal(1,"retry after CRC failure");
        $fdisplay(result_file,"PASS bad CRC rejected before replay and next request recovers");
        low_capacity=1; initialize_card();
        if(error_code!=0 || !card_ready || high_capacity || !cmd16_seen) $fatal(1,"SDSC init %h",error_code);
        read_sector();
        if(error_code!=0 || received_count!=512) $fatal(1,"SDSC read %h",error_code);
        $fdisplay(result_file,"PASS SDSC CMD16 and byte-address conversion");
        absent_flag=1; initialize_card();
        if(error_code!=1 || card_ready) $fatal(1,"no-card did not terminate %h",error_code);
        $fdisplay(result_file,"PASS absent card bounded failure");
        $fdisplay(result_file,"PASS tb_sd_card"); $fclose(result_file); $finish;
    end
    initial begin #1500000000; $fatal(1,"SD watchdog state=%0d",dut.state); end
endmodule
