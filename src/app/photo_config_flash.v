`timescale 1ns/1ps
module photo_config_flash #(
    parameter integer save_delay_ms=1000,
    parameter integer spi_div=8,
    parameter integer startup_cycles=1250000,
    parameter integer wake_cycles=625,
    parameter integer poll_cycles=12500,
    parameter integer timeout_cycles=625000000
) (
    input wire clk, input wire rst_n, input wire tick_1ms,
    input wire menu_active, input wire [25:0] live_data,
    output reg config_apply, output reg [25:0] config_data,
    output reg ready, output wire busy, output reg saved,
    output reg [7:0] error_code,
    output wire flash_cs_n, output wire flash_sclk, output wire flash_mosi,
    input wire flash_miso, output wire flash_wp_n, output wire flash_hold_n
);
    localparam [3:0] st_probe=0, st_probe_wait=1, st_read=2, st_read_wait=3,
        st_crc_load=4, st_crc_wait=5, st_check=6, st_apply=7,
        st_settle=8, st_idle=9, st_write=10, st_write_wait=11, st_error=12, st_check_ready=13;
    localparam integer delay_bits=save_delay_ms>1 ? $clog2(save_delay_ms) : 1;
    localparam [25:0] default_data={3'd1,3'd2,1'b0,2'd0,1'b0,2'd0,3'd0,5'd5,3'd4,3'd4};
    reg [13:0] state;
    reg slot, active_slot, stored_valid;
    reg [31:0] active_version, record_version;
    reg [25:0] saved_data, stable_data, snapshot_data;
    reg [7:0] record_format;
    reg [delay_bits-1:0] idle_count;
    reg [1:0] settle_count;
    reg [15:0] crc;
    reg [7:0] crc_byte;
    reg [2:0] crc_bit;
    reg [3:0] crc_index;
    reg crc_busy, record_bad, record_valid_flag, version_newer_flag;
    reg store_start;
    reg [1:0] store_operation;
    wire store_busy, store_done;
    wire [3:0] store_error;
    wire [7:0] store_raw_byte;
    wire store_raw_valid;
    reg [7:0] store_byte;
    reg store_valid,field_invalid;
    wire [3:0] store_index;
    wire [3:0] record_index=(state[st_crc_load] || state[st_crc_wait]) ? crc_index : store_index;
    reg [7:0] record_byte;
    wire [31:0] version_delta=record_version-active_version;
    assign busy=!state[st_idle] && !state[st_error];
    always @* begin
        case (record_index)
            0: record_byte=8'h42;
            1: record_byte=8'h47;
            2: record_byte=8'h05;
            3: record_byte=8'h10;
            4: record_byte=record_version[31:24];
            5: record_byte=record_version[23:16];
            6: record_byte=record_version[15:8];
            7: record_byte=record_version[7:0];
            8: record_byte={5'd0,snapshot_data[2:0]};
            9: record_byte={5'd0,snapshot_data[5:3]};
            10: record_byte={3'd0,snapshot_data[10:6]};
            11: record_byte={5'd0,snapshot_data[13:11]};
            12: record_byte={3'd0,snapshot_data[19],snapshot_data[18:17],snapshot_data[15:14]};
            13: record_byte={2'd0,snapshot_data[25:23],snapshot_data[22:20]};
            14: record_byte=crc[15:8];
            15: record_byte=crc[7:0];
            default: record_byte=0;
        endcase
    end
    photo_flash_record #(.spi_div(spi_div),.startup_cycles(startup_cycles),
        .wake_cycles(wake_cycles),.poll_cycles(poll_cycles),.timeout_cycles(timeout_cycles)) store_proc (
        .clk(clk),.rst_n(rst_n),.start(store_start),.operation(store_operation),.slot(slot),
        .write_byte(record_byte),.payload_index(store_index),
        .busy(store_busy),.done(store_done),.error_code(store_error),
        .read_byte(store_raw_byte),.read_valid(store_raw_valid),.flash_cs_n(flash_cs_n),.flash_sclk(flash_sclk),
        .flash_mosi(flash_mosi),.flash_miso(flash_miso),.flash_wp_n(flash_wp_n),.flash_hold_n(flash_hold_n)
    );
    function field_invalid_proc;
        input [7:0] value;
        input [3:0] index;
        input [7:0] format;
        begin
            field_invalid_proc=0;
            case(index)
                0:field_invalid_proc=value!=8'h42;
                1:field_invalid_proc=value!=8'h47;
                2:field_invalid_proc=value<1 || value>5;
                3:field_invalid_proc=value!=8'h10;
                8,9:field_invalid_proc=value>4;
                10:field_invalid_proc=value==0 || value>30;
                11:field_invalid_proc=value>(format==1 ? 8'd5 : 8'd6);
                12:if(format>=3)field_invalid_proc=
                    (format>=4 ? value[7:5]!=0 : value[7:4]!=0) || value[1:0]>2 || value[3:2]>2;
                    else field_invalid_proc=format==2 ? value>2 : value!=0;
                13:field_invalid_proc=format==5 ?
                    value[7:6]!=0 || value[2:0]>4 || value[5:3]>4 : format==1 ? value!=0 : value>1;
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin store_byte<=0;store_valid<=0;field_invalid<=0;end
        else begin
            store_valid<=store_raw_valid;
            if(store_raw_valid)begin
                store_byte<=store_raw_byte;
                field_invalid<=field_invalid_proc(store_raw_byte,crc_index,record_format);
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=14'd1<<st_probe; slot<=0; active_slot<=0; stored_valid<=0; active_version<=0; record_version<=0;
            saved_data<=default_data; stable_data<=default_data; snapshot_data<=default_data;
            idle_count<=0; settle_count<=0; crc<=16'hffff;
            crc_byte<=0; crc_bit<=0; crc_index<=0; crc_busy<=0; record_bad<=0;
            record_valid_flag<=0; version_newer_flag<=0;
            record_format<=0;
            store_start<=0; store_operation<=0; config_apply<=0; config_data<=default_data;
            ready<=0; saved<=0; error_code<=0;
        end else begin
            if(store_busy || store_done)store_start<=0;
            config_apply<=0; saved<=0;
            record_valid_flag<=!record_bad && crc==0 && !crc_busy;
            version_newer_flag<=!stored_valid || (record_version!=active_version && !version_delta[31]);
            if (crc_busy) begin
                crc<=(crc[15]^crc_byte[7]) ? {crc[14:0],1'b0}^16'h1021 : {crc[14:0],1'b0};
                crc_byte<={crc_byte[6:0],1'b0};
                if (crc_bit==7) crc_busy<=0;
                else crc_bit<=crc_bit+1'b1;
            end
            (* parallel_case *) case (1'b1)
                state[st_probe]: begin store_operation<=0; store_start<=1; state<=14'd1<<st_probe_wait; end
                state[st_probe_wait]: if (store_done && store_error==0) state<=14'd1<<st_read;
                state[st_read]: begin
                    store_operation<=1; store_start<=1; record_bad<=0;
                    snapshot_data[25:14]<={3'd1,3'd2,6'd0}; record_format<=0;
                    crc<=16'hffff; crc_index<=0; crc_busy<=0; state<=14'd1<<st_read_wait;
                end
                state[st_read_wait]: begin
                    if (store_valid) begin
                        if(field_invalid)record_bad<=1;
                        crc_byte<=store_byte; crc_bit<=0; crc_busy<=1; crc_index<=crc_index+1'b1;
                        case (crc_index)
                            2: begin
                                record_format<=store_byte;
                            end
                            4,5,6,7: record_version<={record_version[23:0],store_byte};
                            8: begin
                                snapshot_data[2:0]<=store_byte[2:0];
                            end
                            9: begin
                                snapshot_data[5:3]<=store_byte[2:0];
                            end
                            10: begin
                                snapshot_data[10:6]<=store_byte[4:0];
                            end
                            11: begin
                                snapshot_data[13:11]<=store_byte[2:0];
                            end
                            12: begin
                                snapshot_data[15:14]<=store_byte[1:0];
                                if (record_format>=3) begin
                                    snapshot_data[18:17]<=store_byte[3:2];
                                    snapshot_data[19]<=record_format>=4 && store_byte[4];
                                end else if (record_format==2) begin
                                end else begin
                                    snapshot_data[15:14]<=0;
                                end
                            end
                            13: begin
                                snapshot_data[16]<=0;
                                if(record_format==5)begin
                                    snapshot_data[22:20]<=store_byte[2:0];snapshot_data[25:23]<=store_byte[5:3];
                                end
                            end
                        endcase
                    end
                    if (store_done && store_error==0) state<=14'd1<<st_check_ready;
                end
                state[st_crc_load]: begin
                    crc_byte<=record_byte; crc_bit<=0; crc_busy<=1; state<=14'd1<<st_crc_wait;
                end
                state[st_crc_wait]: if (!crc_busy) begin
                    if (crc_index==13) state<=14'd1<<st_write;
                    else begin crc_index<=crc_index+1'b1; state<=14'd1<<st_crc_load; end
                end
                state[st_check_ready]: state<=14'd1<<st_check;
                state[st_check]: begin
                    if (record_valid_flag && version_newer_flag) begin
                        stored_valid<=1; active_slot<=slot;
                        active_version<=record_version; saved_data<=snapshot_data;
                    end
                    if (!slot) begin slot<=1; state<=14'd1<<st_read; end
                    else state<=14'd1<<st_apply;
                end
                state[st_apply]: begin
                    config_apply<=stored_valid; config_data<=saved_data;
                    ready<=1; settle_count<=0; state<=14'd1<<st_settle;
                end
                state[st_settle]: if (settle_count==3) begin
                    stable_data<=live_data; idle_count<=0; state<=14'd1<<st_idle;
                end else settle_count<=settle_count+1'b1;
                state[st_idle]: begin
                    if (live_data!=stable_data || live_data==saved_data) begin
                        stable_data<=live_data; idle_count<=0;
                    end else if (tick_1ms) begin
                        if (idle_count==save_delay_ms-1) begin
                            snapshot_data<=live_data;
                            slot<=stored_valid ? !active_slot : 1'b0;
                            record_version<=active_version+32'd1;
                            crc<=16'hffff; crc_index<=0; crc_busy<=0; idle_count<=0; state<=14'd1<<st_crc_load;
                        end else idle_count<=idle_count+1'b1;
                    end
                end
                state[st_write]: begin store_operation<=2; store_start<=1; state<=14'd1<<st_write_wait; end
                state[st_write_wait]: if (store_done && store_error==0) begin
                    stored_valid<=1; active_slot<=slot; active_version<=active_version+1'b1;
                    saved_data<=snapshot_data; stable_data<=live_data; idle_count<=0;
                    saved<=1; state<=14'd1<<st_idle;
                end
                state[st_error]: ready<=1;
                default: begin error_code<=8'hcf; ready<=1; state<=14'd1<<st_error; end
            endcase
            if (store_done && store_error!=0) begin
                error_code<={4'hc,store_error}; ready<=1; state<=14'd1<<st_error;
            end
        end
    end
endmodule
