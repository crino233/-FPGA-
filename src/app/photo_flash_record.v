`timescale 1ns/1ps
module photo_flash_record #(
    parameter integer spi_div = 8,
    parameter integer startup_cycles = 1250000,
    parameter integer wake_cycles = 625,
    parameter integer poll_cycles = 12500,
    parameter integer timeout_cycles = 625000000
) (
    input wire clk, input wire rst_n, input wire start,
    input wire [1:0] operation, input wire slot,
    input wire [7:0] write_byte, output wire [3:0] payload_index,
    output reg busy, output reg done, output reg [3:0] error_code,
    output reg [7:0] read_byte, output reg read_valid,
    output reg flash_cs_n, output wire flash_sclk, output wire flash_mosi,
    input wire flash_miso, output wire flash_wp_n, output wire flash_hold_n
);
    localparam [4:0] st_idle=0, st_power=1, st_wake=2, st_id=3,
        st_status=4, st_status_check=5, st_poll=6, st_status2=7,
        st_erase_check=8, st_verify=9, st_success=10,
        st_byte=11, st_byte_wait=12, st_gap=13;
    localparam integer timer_bits = timeout_cycles>1 ? $clog2(timeout_cycles) : 1;
    localparam integer delay_max = poll_cycles>wake_cycles ? poll_cycles : wake_cycles;
    localparam integer delay_bits = delay_max>8 ? $clog2(delay_max+1) : 4;
    localparam [15:0] spi_div_value=spi_div;
    reg [13:0] state;
    reg [4:0] return_state;
    localparam integer spi_div_bits=spi_div>1 ? $clog2(spi_div) : 1;
    reg [timer_bits-1:0] timer_count;
    reg power_ready, timeout_flag;
    reg read_erased, read_matches, id_matches;
    reg probe_identified;
    reg [delay_bits-1:0] delay_count;
    reg [1:0] held_operation;
    reg held_slot;
    reg [2:0] status_phase;
    reg [31:0] prefix;
    reg [4:0] byte_index, byte_count;
    reg payload_write, byte_start;
    reg [7:0] byte_tx, expected_byte;
    wire byte_busy, byte_done;
    wire [7:0] byte_rx;
    assign payload_index=byte_index[3:0]-4'd4;
    wire [23:0] slot_address = held_slot ? 24'h7ff000 : 24'h7fe000;
    assign flash_wp_n=1'b1;
    assign flash_hold_n=1'b1;
    sd_spi_byte #(.div_bits(spi_div_bits)) byte_proc (
        .clk(clk),.rst_n(rst_n && busy),.start(byte_start),.clk_div(spi_div_value),
        .tx_data(byte_tx),.miso(flash_miso),.busy(byte_busy),.done(byte_done),
        .rx_data(byte_rx),.sclk(flash_sclk),.mosi(flash_mosi)
    );
    task transfer_proc;
        input [31:0] command;
        input [4:0] length;
        input write_payload;
        input [4:0] next_state;
        begin
            prefix<=command; byte_count<=length; byte_index<=0;
            payload_write<=write_payload; return_state<=next_state;
            read_byte<=0; read_erased<=1; read_matches<=1; id_matches<=1;
            flash_cs_n<=0; state<=14'd1<<st_byte;
        end
    endtask
    task fail_proc;
        input [3:0] code;
        begin busy<=0; done<=1; error_code<=code; flash_cs_n<=1; state<=14'd1<<st_idle; end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=14'd1<<st_idle; return_state<=st_idle; busy<=0; done<=0; error_code<=0;
            flash_cs_n<=1; timer_count<=0; delay_count<=0;
            power_ready<=0; timeout_flag<=0;
            read_erased<=0; read_matches<=0; id_matches<=0;
            probe_identified<=0;
            held_operation<=0; held_slot<=0; status_phase<=0;
            prefix<=0; read_byte<=0; read_valid<=0;
            byte_index<=0; byte_count<=0; payload_write<=0; byte_start<=0; byte_tx<=8'hff; expected_byte<=0;
        end else begin
            done<=0; read_valid<=0;
            if(byte_busy || byte_done || !busy)byte_start<=0;
            if (busy) begin
                timer_count<=timer_count+1'b1;
                power_ready<=timer_count>=startup_cycles-1;
                timeout_flag<=timer_count==timeout_cycles-2;
            end
            (* parallel_case *) case (1'b1)
                state[st_idle]: if (start) begin
                    busy<=1; error_code<=0; timer_count<=0; delay_count<=0;
                    power_ready<=0; timeout_flag<=0;
                    probe_identified<=0;
                    held_operation<=operation; held_slot<=slot;
                    status_phase<=0;
                    if (operation==0) state<=14'd1<<st_power;
                    else if (operation==1 || operation==2) state<=14'd1<<st_status;
                    else fail_proc(4'hf);
                end
                state[st_power]: if (power_ready)
                    transfer_proc(32'hab000000,1,0,st_wake);
                state[st_wake]: if (delay_count==wake_cycles-1) begin
                    delay_count<=0; state<=14'd1<<st_status;
                end else delay_count<=delay_count+1'b1;
                state[st_id]: if (!id_matches) fail_proc(1);
                    else begin probe_identified<=1; state<=14'd1<<st_status; end
                state[st_status]: transfer_proc(32'h05ffffff,2,0,st_status_check);
                state[st_status_check]: begin
                    if (read_byte[0]) begin delay_count<=0; state<=14'd1<<st_poll; end
                    else case (status_phase)
                        0: if (held_operation==0) begin
                            if (!probe_identified) transfer_proc(32'h9f000000,4,0,st_id);
                            else if (read_byte[6:2]!=0) fail_proc(2);
                            else if (read_byte[1]) transfer_proc(32'h04000000,1,0,st_status);
                            else transfer_proc(32'h35ffffff,2,0,st_status2);
                        end else if (held_operation==1)
                            transfer_proc({8'h03,slot_address},20,0,st_success);
                        else if (read_byte[6:2]!=0) fail_proc(2);
                        else begin
                            status_phase<=1; transfer_proc(32'h06000000,1,0,st_status);
                        end
                        1: if (!read_byte[1]) fail_proc(3);
                            else begin
                                status_phase<=2;
                                transfer_proc({8'h20,slot_address},4,0,st_status);
                            end
                        2: transfer_proc({8'h03,slot_address},20,0,st_erase_check);
                        3: if (!read_byte[1]) fail_proc(3);
                            else begin
                                status_phase<=4;
                                transfer_proc({8'h02,slot_address},20,1,st_status);
                            end
                        default: transfer_proc({8'h03,slot_address},20,0,st_verify);
                    endcase
                end
                state[st_status2]: if (read_byte[6]) fail_proc(2); else state<=14'd1<<st_success;
                state[st_poll]: if (delay_count==poll_cycles-1) begin delay_count<=0; state<=14'd1<<st_status; end
                    else delay_count<=delay_count+1'b1;
                state[st_erase_check]: if (!read_erased) fail_proc(4);
                    else begin status_phase<=3; transfer_proc(32'h06000000,1,0,st_status); end
                state[st_verify]: if (!read_matches) fail_proc(5); else state<=14'd1<<st_success;
                state[st_success]: begin busy<=0; done<=1; flash_cs_n<=1; state<=14'd1<<st_idle; end
                state[st_byte]: if (!byte_busy) begin
                    byte_tx<=byte_index<4 ? prefix[31:24] : payload_write ? write_byte : 8'hff;
                    expected_byte<=write_byte;
                    byte_start<=1; state<=14'd1<<st_byte_wait;
                end
                state[st_byte_wait]: if (byte_done) begin
                    read_byte<=byte_rx;
                    if (byte_count==4) begin
                        case (byte_index)
                            1: if (byte_rx!=8'hef) id_matches<=0;
                            2: if (byte_rx!=8'h40) id_matches<=0;
                            3: if (byte_rx!=8'h17) id_matches<=0;
                        endcase
                    end
                    if (byte_count==20 && !payload_write && byte_index>=4) begin
                        read_valid<=1;
                        if (byte_rx!=8'hff) read_erased<=0;
                        if (byte_rx!=expected_byte) read_matches<=0;
                    end
                    if (byte_index<4) prefix<={prefix[23:0],8'hff};
                    if (byte_index==byte_count-1'b1) begin
                        flash_cs_n<=1; delay_count<=0; state<=14'd1<<st_gap;
                    end else begin byte_index<=byte_index+1'b1; state<=14'd1<<st_byte; end
                end
                state[st_gap]: if (delay_count==7) begin delay_count<=0; state<=14'd1<<return_state; end
                    else delay_count<=delay_count+1'b1;
                default: fail_proc(4'hf);
            endcase
            if (busy && timeout_flag) fail_proc(6);
        end
    end
endmodule
