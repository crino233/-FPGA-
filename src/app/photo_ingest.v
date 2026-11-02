`timescale 1ns/1ps
module photo_ingest #(
    parameter integer image_width=640,
    parameter integer image_height=480,
    parameter integer group_prefetch=0,
    parameter integer subtitle_support=0,
    parameter integer wav_support=0,
    parameter integer image_scale_support=0
) (
    input wire clk, input wire rst_n,
    input wire controller_ready, input wire controller_busy, input wire refresh_active,
    input wire [3:0] requested_index, input wire [1:0] active_bank, input wire auto_mode,
    input wire display_publish_enable,
    input wire wav_play_enable,input wire wav_pix_clk,input wire wav_pix_rst_n,input wire wav_consume,
    output wire signed [15:0] wav_sample,output wire wav_ready,output wire [7:0] wav_error,
    input wire [9:0] selection_mask,
    input wire memory_grant, output wire memory_request, output wire memory_done,
    output wire display_ready, output wire [1:0] display_bank,
    output wire [3:0] active_index, output wire [3:0] display_index,
    output wire [11:0] active_source_width, output wire [11:0] active_source_height,
    output wire [9:0] valid_mask, output wire [3:0] image_complete, output wire target_ready,
    output reg [3:0] status_code, output reg [7:0] error_code, output reg [7:0] error_detail,
    output reg [15:0] startup_detail,
    input wire subtitle_request, input wire [1:0] subtitle_index, input wire subtitle_done,
    input wire [31:0] subtitle_range_offset, input wire subtitle_close,
    input wire subtitle_service_complete,
    input wire [7:0] subtitle_load_error,
    output wire subtitle_start, output wire subtitle_valid, output wire subtitle_end,
    output wire subtitle_cancelled, output wire subtitle_finished,
    output wire [31:0] subtitle_size, output wire [31:0] subtitle_offset,
    output wire [7:0] subtitle_data, output wire [7:0] subtitle_file_error,
    output wire app_wr_en, output wire [20:0] app_wr_addr,
    output wire [31:0] app_wr_data, output wire [3:0] app_wr_mask,
    output wire sd_cs_n, output wire sd_sclk, output wire sd_mosi, input wire sd_miso
);
    localparam [2:0] st_wait=0, st_init=1, st_catalog=2, st_play=3, st_error=4;
    reg [2:0] state;
    reg init_start, fs_start;
    wire init_done, card_ready, fs_done, fs_busy, catalog_ready, cache_ready;
    wire [4:0] fs_state_debug,card_state_debug;
    wire aux_active,aux_block_done;
    wire fs_file_req, fs_aux_req, fs_cancel;
    reg image_pending, image_request_reg, aux_request_reg;
    reg subtitle_finished_reg;
    reg cancel_reg;
    wire image_file=!(subtitle_support && aux_active);
    wire [7:0] card_error, fs_error, bmp_error, load_error;
    wire [11:0] load_source_width, load_source_height;
    wire sector_req, sector_busy, sector_valid, sector_done;
    wire [31:0] sector_lba;
    wire [7:0] sector_data;
    wire [8:0] sector_index;
    wire card_sector_req,card_sector_busy,card_sector_valid,card_sector_done;
    wire [31:0] card_sector_lba;
    wire image_owner,audio_owner;
    wire audio_sector_req,audio_urgent;
    wire [31:0] audio_sector_lba;
    generate if(wav_support)begin: wav_service_proc
        wire audio_rst_n;
        photo_reset_sync audio_reset_proc(.clk(clk),.reset_req(!rst_n),.rst_n(audio_rst_n));
        wire audio_catalog_ready,audio_busy,audio_done,audio_available;
        wire audio_request,audio_pause,audio_load_done,audio_start,audio_valid,audio_end;
        wire [31:0] audio_size,audio_offset;
        wire [7:0] audio_data,audio_fs_error,audio_load_error;
        reg audio_start_scan;
        reg audio_scanned;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin audio_start_scan<=0;audio_scanned<=0;end
            else begin
                audio_start_scan<=0;
                if(display_ready && !audio_scanned)begin audio_start_scan<=1;audio_scanned<=1;end
            end
        end
        photo_sector_arbiter sector_proc(.clk(clk),.rst_n(rst_n),.audio_urgent(audio_urgent),
            .image_req(sector_req),.image_lba(sector_lba),.audio_req(audio_sector_req),.audio_lba(audio_sector_lba),
            .client_busy(sector_busy),.card_req(card_sector_req),.card_lba(card_sector_lba),
            .card_busy(card_sector_busy),.card_done(card_sector_done),.image_owner(image_owner),.audio_owner(audio_owner));
        photo_fat32 #(.image_count(1),.index_bits(1),.request_mode(1),.audio_catalog(1),.pausable(1),
            .max_chain_clusters(8192)) audio_fs_proc(
            .clk(clk),.rst_n(audio_rst_n),.start(audio_start_scan),.busy(audio_busy),.done(audio_done),
            .error_code(audio_fs_error),.resource_valid(audio_available),.image_index(),.catalog_ready(audio_catalog_ready),
            .file_req(audio_request),.file_req_index(1'b0),.file_cancel(1'b0),.file_pause(audio_pause),.file_cancelled(),
            .aux_req(1'b0),.aux_index(2'd0),.aux_active(),.aux_available(),.aux_error(),
            .sector_req(audio_sector_req),.sector_lba(audio_sector_lba),.sector_busy(sector_busy),
            .sector_valid(card_sector_valid && audio_owner),.sector_data(sector_data),.sector_index(sector_index),
            .sector_done(card_sector_done && audio_owner),.sector_error(audio_owner ? card_error : 8'd0),
            .file_start(audio_start),.file_size(audio_size),.file_valid(audio_valid),.file_data(audio_data),
            .file_offset(audio_offset),.file_end(audio_end),.load_done(audio_load_done),
            .load_error(audio_load_error),.decode_error(8'd0));
        photo_wav_stream stream_proc(.clk(clk),.rst_n(audio_rst_n),.play_enable(wav_play_enable),
            .catalog_ready(audio_catalog_ready),.fs_busy(audio_busy),.fs_done(audio_done),.fs_error(audio_fs_error),
            .available(audio_available),.file_request(audio_request),.file_pause(audio_pause),.load_done(audio_load_done),
            .load_error(audio_load_error),.file_start(audio_start),.file_size(audio_size),.file_valid(audio_valid),
            .file_data(audio_data),.file_offset(audio_offset),.file_end(audio_end),
            .pix_clk(wav_pix_clk),.pix_rst_n(wav_pix_rst_n),.consume(wav_consume),
            .sample_data(wav_sample),.sample_ready(wav_ready),.urgent(audio_urgent),.error_code(wav_error),
            .samples_written(),.underflows());
    end else begin: no_wav_proc
        assign card_sector_req=sector_req;assign card_sector_lba=sector_lba;
        assign sector_busy=card_sector_busy;assign image_owner=1'b1;assign audio_owner=1'b0;
        assign wav_sample=16'd0;assign wav_ready=0;assign wav_error=0;
    end endgenerate
    assign sector_valid=card_sector_valid && image_owner;
    assign sector_done=card_sector_done && image_owner;
    wire file_start, file_valid, file_end, pixel_valid, top_down, frame_commit, load_done;
    wire [31:0] file_size, file_offset;
    wire [7:0] file_data;
    wire [23:0] pixel_data;
    wire file_request, file_cancel, file_cancelled;
    wire [3:0] file_index;
    wire [1:0] load_bank;
    wire [3:0] bank_complete;
    wire image_file_block, loader_pixel_ready, image_stream_end;
    assign display_ready=cache_ready && state!=st_error;
    assign subtitle_start=subtitle_support && aux_active && file_start;
    assign subtitle_valid=subtitle_support && aux_active && file_valid;
    assign subtitle_end=subtitle_support && aux_active && file_end;
    assign subtitle_finished=subtitle_support && subtitle_finished_reg;
    assign subtitle_cancelled=subtitle_support && aux_active && file_cancelled;
    assign subtitle_size=file_size;
    assign subtitle_offset=file_offset;
    assign subtitle_data=file_data;
    assign fs_file_req=subtitle_support ? image_request_reg : file_request;
    assign fs_aux_req=subtitle_support && aux_request_reg;
    assign fs_cancel=subtitle_support ? cancel_reg : file_cancel;
    generate if(subtitle_support)begin: file_service_proc
        wire subtitle_startup_pending=display_ready && !subtitle_service_complete;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin image_pending<=0;image_request_reg<=0;aux_request_reg<=0;subtitle_finished_reg<=0;cancel_reg<=0;end
            else begin
                cancel_reg<=aux_active ? ((image_pending || file_request) && !target_ready) || subtitle_load_error!=0 : file_cancel;
                subtitle_finished_reg<=aux_active && (fs_done || aux_block_done);
                if(fs_busy || file_start || fs_done)begin image_request_reg<=0;aux_request_reg<=0;end
                if(file_request)image_pending<=1;
                if(catalog_ready && !fs_busy && !fs_file_req && !fs_aux_req && !fs_done && state!=st_error)begin
                    if((image_pending || file_request) && (!subtitle_startup_pending || !target_ready))begin
                        image_request_reg<=1;image_pending<=0;
                    end
                    else if(display_ready && subtitle_request)aux_request_reg<=1;
                end
            end
        end
    end endgenerate

    sd_card_reader card_proc (
        .clk(clk),.rst_n(rst_n),.init_start(init_start),.init_done(init_done),
        .card_ready(card_ready),.high_capacity(),.error_code(card_error),
        .sector_req(card_sector_req),.sector_lba(card_sector_lba),.sector_busy(card_sector_busy),
        .sector_valid(card_sector_valid),.sector_data(sector_data),.sector_index(sector_index),
        .sector_done(card_sector_done),.sd_cs_n(sd_cs_n),.sd_sclk(sd_sclk),
        .sd_mosi(sd_mosi),.sd_miso(sd_miso),.state_debug(card_state_debug)
    );
    photo_fat32 #(.image_count(10),.request_mode(1),.auxiliary_files(subtitle_support),.font_ranges(subtitle_support)) fs_proc (
        .clk(clk),.rst_n(rst_n),.start(fs_start),.busy(fs_busy),.done(fs_done),
        .state_debug(fs_state_debug),
        .error_code(fs_error),.resource_valid(valid_mask),.image_index(),
        .catalog_ready(catalog_ready),.file_req(fs_file_req && state!=st_error),.file_req_index(file_index),
        .file_cancel(fs_cancel),.file_pause(1'b0),.file_cancelled(file_cancelled),
        .aux_req(fs_aux_req || (subtitle_request && subtitle_index==2 && aux_active && fs_busy)),
        .aux_index(subtitle_index),.aux_active(aux_active),.aux_available(),
        .aux_offset(subtitle_range_offset),.aux_close(subtitle_close),.aux_block_done(aux_block_done),
        .aux_error(subtitle_file_error),
        .sector_req(sector_req),.sector_lba(sector_lba),
        .sector_busy(sector_busy || (image_file && image_file_block)),
        .sector_valid(sector_valid),.sector_data(sector_data),.sector_index(sector_index),
        .sector_done(sector_done),.sector_error(image_owner ? card_error : 8'd0),
        .file_start(file_start),.file_size(file_size),.file_valid(file_valid),
        .file_data(file_data),.file_offset(file_offset),.file_end(file_end),
        .load_done(image_file ? load_done : subtitle_done),
        .load_error(image_file ? load_error : subtitle_load_error),.decode_error(image_file ? bmp_error : 8'd0)
    );
    generate if(image_scale_support)begin: image_scale_proc
        photo_image_scale #(.image_width(image_width),.image_height(image_height)) scale_proc (
            .clk(clk),.rst_n(rst_n),.file_start(file_start && image_file),.file_size(file_size),
            .file_valid(file_valid && image_file),.file_data(file_data),.file_offset(file_offset),
            .file_end(file_end && image_file),.file_cancelled(file_cancelled && image_file),
            .upstream_error(fs_error),.file_block(image_file_block),.pixel_ready(loader_pixel_ready),
            .pixel_valid(pixel_valid),.pixel_data(pixel_data),.top_down(top_down),
            .frame_commit(frame_commit),.stream_end(image_stream_end),.error_code(bmp_error),
            .source_width_out(load_source_width),.source_height_out(load_source_height));
    end else begin: fixed_image_proc
    assign image_file_block=1'b0;
    assign image_stream_end=file_end && image_file;
    assign load_source_width=image_width;
    assign load_source_height=image_height;
    photo_bmp_decoder #(.image_width(image_width),.image_height(image_height)) bmp_proc (
        .clk(clk),.rst_n(rst_n),.file_start(file_start && image_file),.file_size(file_size),
        .file_valid(file_valid && image_file),.file_data(file_data),.file_offset(file_offset),
        .file_end(file_end && image_file),.upstream_error(fs_error),.pixel_valid(pixel_valid),
        .pixel_data(pixel_data),.top_down(top_down),.frame_commit(frame_commit),.error_code(bmp_error)
    );
    end endgenerate
    photo_frame_loader #(.image_width(image_width),.image_height(image_height),.arbitrated(1)) load_proc (
        .clk(clk),.rst_n(rst_n),.load_start(file_start && image_file),.image_index(load_bank),
        .pixel_valid(pixel_valid),.pixel_data(pixel_data),.top_down(top_down),
        .frame_commit(frame_commit),.load_end(image_stream_end),.load_cancel(file_cancelled && image_file),
        .decode_error(bmp_error),.upstream_error(fs_error),
        .controller_ready(controller_ready),.controller_busy(controller_busy),.refresh_active(refresh_active),
        .memory_grant(memory_grant),.memory_request(memory_request),.memory_done(memory_done),
        .load_busy(),.load_done(load_done),.pixel_ready(loader_pixel_ready),.image_complete(bank_complete),.error_code(load_error),
        .app_wr_en(app_wr_en),.app_wr_addr(app_wr_addr),.app_wr_data(app_wr_data),.app_wr_mask(app_wr_mask)
    );
    photo_cache_control #(.group_prefetch(group_prefetch)) cache_proc (
        .clk(clk),.rst_n(rst_n),.catalog_ready(catalog_ready),.valid_mask(valid_mask),
        .requested_index(requested_index),.active_bank(active_bank),.auto_mode(auto_mode),
        .display_publish_enable(display_publish_enable),
        .selection_mask(selection_mask),
        .load_source_width(load_source_width),.load_source_height(load_source_height),
        .file_done(fs_done && image_file),.file_cancelled(file_cancelled && image_file),.bank_complete(bank_complete),
        .file_request(file_request),.file_cancel(file_cancel),.file_index(file_index),.load_bank(load_bank),
        .display_ready(cache_ready),.display_bank(display_bank),.display_index(display_index),
        .active_index(active_index),.active_source_width(active_source_width),
        .active_source_height(active_source_height),.cache_valid(image_complete),.target_ready(target_ready)
    );
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=st_wait; init_start<=0; fs_start<=0;
            status_code<=0; error_code<=0; error_detail<=0;startup_detail<=0;
        end else begin
            init_start<=0;
            if(fs_busy || catalog_ready || fs_done)fs_start<=0;
            startup_detail<={catalog_ready,fs_busy,fs_start,fs_state_debug,
                image_pending,image_file_block,card_sector_busy,card_state_debug};
            case(state)
                st_wait: if(controller_ready) begin init_start<=1; status_code<=1; state<=st_init; end
                st_init: if(init_done) begin
                    if(!card_ready || card_error!=0) begin
                        error_code<=card_error; error_detail<=card_error; status_code<=4'he; state<=st_error;
                    end else begin fs_start<=1; status_code<=2; state<=st_catalog; end
                end
                st_catalog,st_play: begin
                    if(cache_ready) begin status_code<=3; state<=st_play; end
                    if(catalog_ready && valid_mask==0) begin
                        error_code<=8'he6; error_detail<=bmp_error; status_code<=4'he; state<=st_error;
                    end
                    if(fs_error!=0) begin
                        error_code<=fs_error;
                        error_detail<=fs_error==8'h20 && card_error!=0 ? card_error : fs_error;
                        status_code<=4'he; state<=st_error;
                    end
                end
                st_error: ;
                default: begin error_code<=8'hff; status_code<=4'he; state<=st_error; end
            endcase
        end
    end
endmodule
