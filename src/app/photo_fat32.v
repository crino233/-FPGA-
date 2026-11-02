`timescale 1ns/1ps
module photo_fat32 #(
    parameter integer clk_freq_hz = 125000000,
    parameter integer max_chain_clusters = 2048,
    parameter integer image_count = 4,
    parameter integer request_mode = 0,
    parameter integer index_bits = $clog2(image_count),
    parameter integer auxiliary_files = 0,
    parameter integer audio_catalog = 0,
    parameter integer pausable = 0,
    parameter integer font_ranges = 0
) (
    input wire clk, input wire rst_n, input wire start,
    output wire busy, output reg done, output reg [7:0] error_code,
    output wire [4:0] state_debug,
    output reg [image_count-1:0] resource_valid,
    output reg [index_bits-1:0] image_index,
    output reg catalog_ready,
    input wire file_req, input wire file_cancel, input wire file_pause, input wire [index_bits-1:0] file_req_index,
    output reg file_cancelled,
    input wire aux_req, input wire [1:0] aux_index,
    input wire [31:0] aux_offset, input wire aux_close,
    output reg aux_block_done,
    output reg aux_active, output reg [2:0] aux_available, output reg [7:0] aux_error,
    output reg sector_req, output reg [31:0] sector_lba,
    input wire sector_busy, input wire sector_valid,
    input wire [7:0] sector_data, input wire [8:0] sector_index,
    input wire sector_done, input wire [7:0] sector_error,
    output reg file_start, output reg [31:0] file_size,
    output reg file_valid, output reg [7:0] file_data,
    output reg [31:0] file_offset, output reg file_end,
    input wire load_done, input wire [7:0] load_error, input wire [7:0] decode_error
);
    localparam [4:0] st_idle=0, st_boot_req=1, st_boot_wait=2,
        st_boot_parse=3, st_layout=4, st_root_begin=5,
        st_root_req=6, st_root_wait=7, st_select=8,
        st_data_req=9, st_data_wait=10, st_load_wait=11,
        st_fat_req=12, st_fat_wait=13, st_fat_parse=14,
        st_loop_wait=15, st_loop_check=16, st_chain_accept=17,
        st_layout_reserved=18, st_layout_data=19, st_layout_cluster=20,
        st_layout_limit=21, st_layout_check=22, st_cluster_offset=23,
        st_cluster_shift=24, st_cluster_address=25, st_file_check=26, st_loop_decide=27,
        st_layout_validate=28, st_file_validate=29, st_font_wait=30, st_font_seek=31;
    localparam integer visit_bits = $clog2(max_chain_clusters);
    reg [4:0] state;
    assign state_debug=state;
    reg partition_flag, partition_loaded, root_flag, directory_end;
    reg partition_check, partition_match, sector_failed, sector_done_buf;
    reg bpb_format_invalid, bpb_cluster_invalid, bpb_fat_invalid;
    reg [31:0] candidate_lba, candidate_size;
    reg [31:0] partition_lba, partition_size;
    reg [127:0] partition_buf;
    reg [255:0] entry_buf;
    wire [127:0] partition_data = {sector_data, partition_buf[127:8]};
    wire [255:0] entry_data = {sector_data, entry_buf[255:8]};
    reg [15:0] signature, bytes_per_sector, reserved_sectors, root_entries;
    reg [15:0] fat16_size, ext_flags, fs_version;
    reg [7:0] sectors_per_cluster, fat_count;
    reg [31:0] total_sectors, fat_sectors, root_cluster;
    reg [2:0] cluster_shift;
    reg [31:0] fat_start, data_start, max_cluster;
    reg [31:0] current_cluster, next_cluster, bytes_left, stream_pos;
    reg [3:0] loop_parts;
    reg loop_last, file_invalid;
    reg fat_invalid, fat_eoc, layout_range_invalid, layout_table_invalid, more_sectors;
    reg [7:0] cluster_last;
    reg [7:0] sector_in_cluster;
    reg [31:0] file_cluster [0:image_count-1];
    reg [31:0] file_length [0:image_count-1];
    localparam integer aux_count=font_ranges ? 3 : 2;
    reg [31:0] aux_cluster [0:aux_count-1], aux_length [0:aux_count-1];
    reg [1:0] aux_selected;
    reg [22:0] font_sector;
    wire font_active=font_ranges && aux_active && aux_selected==2;
    reg [31:0] fat_entry;
    reg [8:0] fat_offset;
    reg [31:0] wait_tick;
    reg [27:0] visited_mem [0:max_chain_clusters-1];
    wire [27:0] visited_data;
    reg [27:0] visited_write_data;
    reg [visit_bits:0] visited_count;
    reg [visit_bits-1:0] check_index, visited_write_addr;
    reg visited_write;
    reg [32:0] fat_span, reserved_span, data_start_sum, volume_end, needed_entries;
    reg [31:0] data_sectors, cluster_count, fat_base, cluster_offset, cluster_sector;
    reg layout_invalid;
    wire [39:0] fat_capacity = {1'b0,fat_sectors,7'b0};
    wire entry_ten = entry_data[31:24] == "1" && entry_data[39:32] == "0";
    wire [3:0] entry_number = audio_catalog ? 4'd0 : entry_ten ? 9 : entry_data[31:24]-8'h31;
    wire [index_bits-1:0] entry_index = entry_number;
    wire entry_match = audio_catalog ?
        (entry_data[87:0]==88'h56415720202020204d4742 && (entry_data[95:88]&8'h18)==0) :
        entry_data[7:0] == "P" && entry_data[15:8] == "I" &&
        entry_data[23:16] == "C" && entry_number < image_count &&
        ((entry_ten && image_count >= 10) ||
         (entry_data[31:24] >= "1" && entry_data[31:24] <= "9" &&
          entry_data[39:32] == " ")) && entry_data[63:40] == 24'h202020 &&
        entry_data[71:64] == "B" && entry_data[79:72] == "M" &&
        entry_data[87:80] == "P" && (entry_data[95:88] & 8'h18) == 0;
    wire aux_notice=entry_data[87:0]==88'h5458542020454349544f4e;
    wire aux_teacher=entry_data[87:0]==88'h5458542052454843414554;
    wire aux_font=font_ranges && entry_data[87:0]==88'h4e494220203631544e4f46;
    wire [1:0] aux_entry=aux_font ? 2'd2 : {1'b0,aux_teacher};
    assign busy = state != st_idle;
    generate if(audio_catalog)begin: audio_history_proc
        EG_LOGIC_BRAM #(.DATA_WIDTH_A(28),.DATA_WIDTH_B(28),
            .ADDR_WIDTH_A(visit_bits),.ADDR_WIDTH_B(visit_bits),
            .DATA_DEPTH_A(max_chain_clusters),.DATA_DEPTH_B(max_chain_clusters),
            .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),.MODE("DP"),
            .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
            .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K"),.INIT_FILE("NONE")) history_proc(
            .clka(clk),.cea(visited_write),.ocea(1'b1),.wea(visited_write),.rsta(1'b0),.bea(1'b1),
            .addra(visited_write_addr),.dia(visited_write_data),.doa(),
            .clkb(clk),.ceb(state==st_loop_wait),.oceb(1'b1),.web(1'b0),.rstb(1'b0),.beb(1'b1),
            .addrb(check_index),.dib(28'd0),.dob(visited_data));
    end else begin: image_history_proc
        reg [27:0] read_data;
        assign visited_data=read_data;
        always @(posedge clk)begin
            if(visited_write)visited_mem[visited_write_addr]<=visited_write_data;
            if(state==st_loop_wait)read_data<=visited_mem[check_index];
        end
    end endgenerate
    function [2:0] cluster_shift_proc;
        input [7:0] value;
        begin
            case (value)
                2: cluster_shift_proc=1; 4: cluster_shift_proc=2;
                8: cluster_shift_proc=3; 16: cluster_shift_proc=4;
                32: cluster_shift_proc=5; 64: cluster_shift_proc=6;
                128: cluster_shift_proc=7; default: cluster_shift_proc=0;
            endcase
        end
    endfunction
    task fail_proc;
        input [7:0] code;
        begin
            if(auxiliary_files && aux_active) aux_error<=code;
            else error_code <= code;
            file_end <= 1; done <= 1; state <= st_idle;
        end
    endtask
    task history_begin;
        input [31:0] cluster;
        begin
            visited_count <= 1; check_index <= 0;
            visited_write <= 1; visited_write_addr <= 0;
            visited_write_data <= cluster[27:0];
        end
    endtask
    task fat_begin;
        begin
            sector_lba <= fat_start+(current_cluster >> 7);
            fat_offset <= {current_cluster[6:0],2'b00};
            fat_entry <= 0; state <= st_fat_req;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= st_idle; done <= 0; error_code <= 0; resource_valid <= 0; catalog_ready <= 0;
            image_index <= 0; sector_req <= 0; sector_lba <= 0;
            file_start <= 0; file_size <= 0; file_valid <= 0; file_data <= 0;
            file_offset <= 0; file_end <= 0; partition_flag <= 0;
            file_cancelled <= 0;
            aux_active<=0;aux_available<=0;aux_error<=0;aux_selected<=0;
            for(integer i=0;i<aux_count;i=i+1)begin aux_cluster[i]<=0;aux_length[i]<=0;end
            font_sector<=0;aux_block_done<=0;
            partition_loaded <= 0; root_flag <= 0; directory_end <= 0;
            partition_check <= 0; partition_match <= 0; candidate_lba <= 0; candidate_size <= 0;
            sector_failed <= 0; sector_done_buf <= 0;
            bpb_format_invalid <= 1; bpb_cluster_invalid <= 1; bpb_fat_invalid <= 1;
            partition_lba <= 0; partition_size <= 0; partition_buf <= 0;
            entry_buf <= 0; signature <= 0; bytes_per_sector <= 0;
            reserved_sectors <= 0; root_entries <= 0; fat16_size <= 0;
            ext_flags <= 0; fs_version <= 0; sectors_per_cluster <= 0;
            fat_count <= 0; total_sectors <= 0; fat_sectors <= 0;
            root_cluster <= 0; cluster_shift <= 0; fat_start <= 0;
            data_start <= 0; max_cluster <= 0; current_cluster <= 0;
            next_cluster <= 0; bytes_left <= 0; sector_in_cluster <= 0;
            stream_pos <= 0; loop_parts <= 0; loop_last <= 0; file_invalid <= 0;
            fat_invalid <= 0; fat_eoc <= 0; layout_range_invalid <= 0;
            layout_table_invalid <= 0; more_sectors <= 0; cluster_last <= 0;
            fat_entry <= 0; fat_offset <= 0; wait_tick <= 0;
            visited_count <= 0; check_index <= 0; visited_write <= 0;
            visited_write_addr <= 0; visited_write_data <= 0;
            fat_span <= 0; reserved_span <= 0; data_start_sum <= 0;
            volume_end <= 0; needed_entries <= 0; data_sectors <= 0;
            cluster_count <= 0; fat_base <= 0; cluster_offset <= 0;
            cluster_sector <= 0; layout_invalid <= 0;
        end else begin
            done <= 0; file_start <= 0; file_valid <= 0;aux_block_done<=0;
            file_end <= 0; sector_req <= 0; visited_write <= 0;
            partition_check <= 0;
            sector_failed <= sector_error != 0;
            sector_done_buf <= sector_done;
            bpb_format_invalid <= bytes_per_sector != 512 || root_entries != 0 || fat16_size != 0 || fs_version != 0;
            bpb_cluster_invalid <= sectors_per_cluster == 0 ||
                (sectors_per_cluster & (sectors_per_cluster-1'b1)) != 0 || root_cluster < 2;
            bpb_fat_invalid <= reserved_sectors == 0 || (fat_count != 1 && fat_count != 2) ||
                fat_sectors == 0 || (ext_flags[7] && ext_flags[3:0] >= fat_count);
            fat_invalid <= fat_entry[27:0] < 2 || fat_entry[27:0] > max_cluster;
            fat_eoc <= fat_entry[27:0] >= 28'hffffff8;
            more_sectors <= sector_in_cluster != cluster_last;
            if (partition_check && partition_match && candidate_lba != 0 &&
                candidate_size != 0 && !partition_flag) begin
                partition_lba <= candidate_lba; partition_size <= candidate_size; partition_flag <= 1;
            end
            if (state == st_idle || sector_valid || load_done || (pausable && file_pause && state==st_data_req)) wait_tick <= 0;
            else wait_tick <= wait_tick+1'b1;
            if (state == st_boot_wait && sector_valid) begin
                case (sector_index)
                    11,12: bytes_per_sector[(sector_index-11)*8 +: 8] <= sector_data;
                    13: sectors_per_cluster <= sector_data;
                    14,15: reserved_sectors[(sector_index-14)*8 +: 8] <= sector_data;
                    16: fat_count <= sector_data;
                    17,18: root_entries[(sector_index-17)*8 +: 8] <= sector_data;
                    22,23: fat16_size[(sector_index-22)*8 +: 8] <= sector_data;
                    32,33,34,35: total_sectors[(sector_index-32)*8 +: 8] <= sector_data;
                    36,37,38,39: fat_sectors[(sector_index-36)*8 +: 8] <= sector_data;
                    40,41: ext_flags[(sector_index-40)*8 +: 8] <= sector_data;
                    42,43: fs_version[(sector_index-42)*8 +: 8] <= sector_data;
                    44,45,46,47: root_cluster[(sector_index-44)*8 +: 8] <= sector_data;
                    510,511: signature[(sector_index-510)*8 +: 8] <= sector_data;
                endcase
                if (sector_index >= 446 && sector_index <= 509 && !partition_loaded) begin
                    partition_buf <= partition_data;
                    if (sector_index[3:0] == 13) begin
                        partition_check <= 1;
                        partition_match <= partition_data[39:32] == 8'h0b || partition_data[39:32] == 8'h0c;
                        candidate_lba <= partition_data[95:64]; candidate_size <= partition_data[127:96];
                    end
                end
            end
            if (state == st_root_wait && sector_valid) begin
                entry_buf <= entry_data;
                if (sector_index[4:0] == 31 && !directory_end) begin
                    if (entry_data[7:0] == 0) directory_end <= 1;
                    else if (entry_match && !resource_valid[entry_index]) begin
                        resource_valid[entry_index] <= 1;
                        file_cluster[entry_index] <= {entry_data[175:168],entry_data[167:160],
                                                     entry_data[223:216],entry_data[215:208]};
                        file_length[entry_index] <= entry_data[255:224];
                    end
                    if(auxiliary_files && (aux_notice || aux_teacher || aux_font) &&
                        (entry_data[95:88]&8'h18)==0 && !directory_end && !aux_available[aux_entry])begin
                        aux_available[aux_entry]<=1;
                        aux_cluster[aux_entry]<={entry_data[175:168],entry_data[167:160],
                            entry_data[223:216],entry_data[215:208]};
                        aux_length[aux_entry]<=entry_data[255:224];
                    end
                end
            end
            if (state == st_fat_wait && sector_valid && sector_index[8:2] == fat_offset[8:2])
                case (sector_index[1:0])
                    0: fat_entry[7:0] <= sector_data;
                    1: fat_entry[15:8] <= sector_data;
                    2: fat_entry[23:16] <= sector_data;
                    3: fat_entry[31:24] <= sector_data;
                endcase
            if (state == st_data_wait && sector_valid && bytes_left != 0) begin
                file_valid <= 1; file_data <= sector_data;
                file_offset <= stream_pos; stream_pos <= stream_pos+1'b1;
                bytes_left <= bytes_left-1'b1;
            end
            case (state)
                st_idle: if (start) begin
                    error_code <= 0; resource_valid <= 0; partition_flag <= 0; catalog_ready <= 0;
                    aux_active<=0;aux_available<=0;aux_error<=0;
                    root_flag <= 1;
                    partition_loaded <= 0; partition_lba <= 0;
                    signature <= 0; sector_lba <= 0; state <= st_boot_req;
                end else if (request_mode && catalog_ready && file_req && file_req_index < image_count) begin
                    aux_active<=0;
                    image_index <= file_req_index; done <= 0; error_code <= 0; state <= st_select;
                end else if(auxiliary_files && request_mode && catalog_ready && aux_req && aux_index<aux_count)begin
                    aux_active<=1;aux_selected<=aux_index;aux_error<=0;file_cancelled<=0;
                    font_sector<=font_ranges ? aux_offset[31:9] : 23'd0;
                    done<=0;state<=st_select;
                end
                st_boot_req: if (!sector_busy) begin sector_req <= 1; state <= st_boot_wait; end
                st_boot_wait: if (sector_done_buf) begin
                    if (sector_failed) fail_proc(8'h20); else state <= st_boot_parse;
                end
                st_boot_parse: begin
                    if (signature != 16'haa55) fail_proc(8'h21);
                    else if (!partition_loaded && bytes_per_sector != 512 && partition_flag) begin
                        sector_lba <= partition_lba; partition_loaded <= 1;
                        signature <= 0; state <= st_boot_req;
                    end else if (bpb_format_invalid || bpb_cluster_invalid || bpb_fat_invalid)
                        fail_proc(8'h22);
                    else begin
                        if (!partition_loaded) partition_lba <= 0;
                        cluster_shift <= cluster_shift_proc(sectors_per_cluster);
                        state <= st_layout;
                    end
                end
                st_layout: begin
                    cluster_last <= sectors_per_cluster-1'b1;
                    fat_span <= fat_count == 2 ? {fat_sectors,1'b0} : {1'b0,fat_sectors};
                    volume_end <= {1'b0,partition_lba}+total_sectors;
                    fat_base <= partition_lba+reserved_sectors;
                    state <= st_layout_reserved;
                end
                st_layout_reserved: begin
                    reserved_span <= fat_span+reserved_sectors;
                    fat_start <= fat_base+((ext_flags[7] && ext_flags[0]) ? fat_sectors : 0);
                    state <= st_layout_data;
                end
                st_layout_data: begin
                    data_start_sum <= {1'b0,partition_lba}+reserved_span;
                    data_sectors <= total_sectors-reserved_span[31:0];
                    layout_invalid <= reserved_span >= total_sectors || volume_end[32] ||
                        (partition_loaded && total_sectors > partition_size);
                    state <= st_layout_cluster;
                end
                st_layout_cluster: begin
                    cluster_count <= data_sectors >> cluster_shift;
                    data_start <= data_start_sum[31:0];
                    layout_invalid <= layout_invalid || data_start_sum[32];
                    state <= st_layout_limit;
                end
                st_layout_limit: begin
                    max_cluster <= cluster_count+1'b1;
                    needed_entries <= {1'b0,cluster_count}+2;
                    layout_range_invalid <= cluster_count < 65525 || cluster_count > 32'h0fffffee;
                    state <= st_layout_validate;
                end
                st_layout_validate: begin
                    layout_table_invalid <= fat_capacity < {7'd0,needed_entries} || root_cluster > max_cluster;
                    state <= st_layout_check;
                end
                st_layout_check: begin
                    if (layout_invalid || layout_range_invalid || layout_table_invalid)
                        fail_proc(8'h22);
                    else begin
                        current_cluster <= root_cluster; root_flag <= 1;
                        history_begin(root_cluster); state <= st_root_begin;
                    end
                end
                st_root_begin: begin
                    sector_in_cluster <= 0; directory_end <= 0;
                    state <= st_cluster_offset;
                end
                st_cluster_offset: begin cluster_offset <= current_cluster-2; state <= st_cluster_shift; end
                st_cluster_shift: begin cluster_sector <= cluster_offset << cluster_shift; state <= st_cluster_address; end
                st_cluster_address: begin
                    sector_lba <= data_start+cluster_sector;
                    state <= root_flag ? st_root_req : st_data_req;
                end
                st_root_req: if (!sector_busy) begin sector_req <= 1; state <= st_root_wait; end
                st_root_wait: if (sector_done_buf) begin
                    if (sector_failed) fail_proc(8'h20);
                    else if ((!auxiliary_files && &resource_valid) || (request_mode && directory_end)) begin
                        if (request_mode) begin catalog_ready <= 1; state <= st_idle; end
                        else begin image_index <= 0; state <= st_select; end
                    end else if (directory_end) fail_proc(8'h23);
                    else if (more_sectors) begin
                        sector_in_cluster <= sector_in_cluster+1'b1;
                        sector_lba <= sector_lba+1'b1; state <= st_root_req;
                    end else fat_begin();
                end
                st_select: begin
                    current_cluster <= auxiliary_files && aux_active ? aux_cluster[aux_selected] : file_cluster[image_index];
                    file_size <= auxiliary_files && aux_active ? aux_length[aux_selected] : file_length[image_index];
                    file_cancelled<=0;state <= st_file_validate;
                end
                st_file_validate: begin
                    file_invalid <= auxiliary_files && aux_active ?
                        (!aux_available[aux_selected] || (file_size!=0 && (current_cluster<2 || current_cluster>max_cluster))) :
                        (!resource_valid[image_index] || current_cluster < 2 || current_cluster > max_cluster || file_size < (audio_catalog ? 44 : 54));
                    state <= st_file_check;
                end
                st_file_check: begin
                    if (file_invalid)
                        begin
                            if(auxiliary_files && aux_active)begin
                                aux_error<=8'h81;file_start<=1;file_end<=1;done<=1;state<=st_idle;
                            end else begin
                            resource_valid[image_index] <= 0;
                            error_code <= 0;
                            if (request_mode || image_index == image_count-1) begin
                                done <= 1; state <= st_idle;
                            end else begin
                                image_index <= image_index+1'b1; state <= st_select;
                            end
                            end
                        end
                    else begin
                        root_flag <= 0; bytes_left <= file_size;
                        file_offset <= 0; stream_pos <= 0; sector_in_cluster <= 0; file_start <= 1;
                        history_begin(current_cluster);
                        if(auxiliary_files && aux_active && file_size==0)begin
                            file_end<=1;state<=st_load_wait;
                        end else state <= st_cluster_offset;
                    end
                end
                st_data_req: if (!sector_busy && (!pausable || !file_pause)) begin
                    if(request_mode && file_cancel)begin
                        file_end<=1;file_cancelled<=1;state<=st_load_wait;
                    end else if(font_active && {font_sector,9'd0}>=file_size)fail_proc(8'h85);
                    else if(font_active && stream_pos[31:9]<font_sector)begin
                        stream_pos<=stream_pos+32'd512;bytes_left<=bytes_left-32'd512;
                        if(sector_in_cluster!=cluster_last)begin
                            sector_in_cluster<=sector_in_cluster+1'b1;sector_lba<=sector_lba+1'b1;
                        end else begin sector_in_cluster<=0;fat_begin();end
                    end else begin sector_req<=1;state<=st_data_wait;end
                end
                st_data_wait: if (sector_done_buf) begin
                    if (sector_failed) fail_proc(8'h20);
                    else if(request_mode && file_cancel)begin
                        file_end<=1;file_cancelled<=1;state<=st_load_wait;
                    end
                    else if (decode_error != 0 || load_error != 0) begin
                        file_end <= 1; state <= st_load_wait;
                    end
                    else if(font_active)begin file_end<=1;state<=st_load_wait;end
                    else if (bytes_left == 0 || (bytes_left == 1 && sector_valid)) begin
                        file_end <= 1; state <= st_load_wait;
                    end else if (more_sectors) begin
                        sector_in_cluster <= sector_in_cluster+1'b1;
                        sector_lba <= sector_lba+1'b1; state <= st_data_req;
                    end else begin sector_in_cluster <= 0; fat_begin(); end
                end
                st_load_wait: if (load_done) begin
                    if (file_cancelled) begin done <= 1; state <= st_idle; end
                    else if(font_active && load_error==0)begin aux_block_done<=1;state<=st_font_wait;end
                    else if(auxiliary_files && aux_active)begin
                        aux_error<=load_error;done<=1;state<=st_idle;
                    end
                    else if (load_error != 0) begin
                        resource_valid[image_index] <= 0;
                        error_code <= 0;
                        if (request_mode || image_index == image_count-1) begin
                            done <= 1; state <= st_idle;
                        end else begin
                            image_index <= image_index+1'b1; state <= st_select;
                        end
                    end
                    else if (request_mode || image_index == image_count-1) begin done <= 1; state <= st_idle; end
                    else begin image_index <= image_index+1'b1; state <= st_select; end
                end
                st_font_wait:begin
                    if(file_cancel)begin file_cancelled<=1;file_end<=1;done<=1;state<=st_idle;end
                    else if(aux_close || load_error!=0)begin aux_error<=load_error;done<=1;state<=st_idle;end
                    else if(aux_req)begin
                        font_sector<=aux_offset[31:9];file_start<=1;state<=st_font_seek;
                    end
                end
                st_font_seek:begin
                    if({font_sector,9'd0}>=file_size || {font_sector,9'd0}<stream_pos)fail_proc(8'h85);
                    else if(more_sectors)begin
                        sector_in_cluster<=sector_in_cluster+1'b1;sector_lba<=sector_lba+1'b1;state<=st_data_req;
                    end else begin sector_in_cluster<=0;fat_begin();end
                end
                st_fat_req: if (!sector_busy) begin sector_req <= 1; state <= st_fat_wait; end
                st_fat_wait: if (sector_done_buf) begin
                    if (sector_failed) fail_proc(8'h20); else state <= st_fat_parse;
                end
                st_fat_parse: begin
                    next_cluster <= {4'd0,fat_entry[27:0]};
                    if (fat_eoc && root_flag && request_mode) begin
                        catalog_ready <= 1; state <= st_idle;
                    end else if (fat_eoc) fail_proc(root_flag ? 8'h23 : 8'h25);
                    else if (fat_invalid)
                        fail_proc(8'h24);
                    else if (visited_count >= max_chain_clusters) fail_proc(8'h27);
                    else begin check_index <= 0; state <= st_loop_wait; end
                end
                st_loop_wait: state <= st_loop_check;
                st_loop_check: begin
                    loop_parts <= {visited_data[27:21] == next_cluster[27:21],
                                   visited_data[20:14] == next_cluster[20:14],
                                   visited_data[13:7] == next_cluster[13:7],
                                   visited_data[6:0] == next_cluster[6:0]};
                    loop_last <= {1'b0,check_index}+1'b1 == visited_count;
                    state <= st_loop_decide;
                end
                st_loop_decide: begin
                    if (&loop_parts) fail_proc(8'h26);
                    else if (loop_last) state <= st_chain_accept;
                    else begin check_index <= check_index+1'b1; state <= st_loop_wait; end
                end
                st_chain_accept: begin
                    visited_write <= 1; visited_write_addr <= visited_count[visit_bits-1:0];
                    visited_write_data <= next_cluster[27:0]; visited_count <= visited_count+1'b1;
                    current_cluster <= next_cluster;
                    if (root_flag) state <= st_root_begin;
                    else state <= st_cluster_offset;
                end
                default: fail_proc(8'h2f);
            endcase
            if (state != st_idle && wait_tick >= clk_freq_hz) fail_proc(8'h2e);
        end
    end
endmodule
