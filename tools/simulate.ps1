param(
    [string[]]$tests = @('tb_photo_audio_product','tb_photo_wav','tb_photo_wav_errors','tb_photo_status_osd','tb_photo_wav_full','tb_photo_subtitle', 'tb_photo_subtitle_fat_1', 'tb_photo_subtitle_fat_2', 'tb_photo_subtitle_fat_3', 'tb_photo_subtitle_manual', 'tb_photo_subtitle_full', 'tb_photo_audio', 'tb_photo_audio_ten', 'tb_photo_scene_audio', 'tb_photo_config_flash', 'tb_photo_control', 'tb_photo_badge', 'tb_photo_exam_timer', 'tb_photo_overlay', 'tb_photo_transition', 'tb_sd_card', 'tb_sd_reset', 'tb_sd_reset_full', 'tb_bmp_edges', 'tb_photo_pipeline', 'tb_photo_sdram', 'tb_photo_cache', 'tb_photo_cache_group', 'tb_photo_group', 'tb_photo_group_full', 'tb_photo_ten', 'tb_photo_ten_bad_first', 'tb_photo_ten_all_bad', 'tb_photo_ten_full', 'tb_photo_ten_scene', 'tb_photo_ten_scene_full', 'tb_photo_ten_transition_full_fade', 'tb_photo_ten_transition_full_wipe', 'tb_photo_exam_return', 'tb_photo_exam_return_full', 'tb_photo_scene_switch_0', 'tb_photo_scene_switch_1', 'tb_photo_scene_switch_2', 'tb_photo_manual_priority_0', 'tb_photo_manual_priority_1', 'tb_photo_manual_priority_2', 'tb_photo_manual_priority_full'),
    [string]$library = 'work',
    [string]$model_bin = $(if ($env:MODELSIM_BIN) { $env:MODELSIM_BIN } else { 'D:/plan_B/modelsim/win64' }),
    [string]$td_root = $(if ($env:ANLU_TD_ROOT) { $env:ANLU_TD_ROOT } else { 'D:/plan_B/anlu' }),
    [string]$temp_dir = (Join-Path $env:PUBLIC 'fpga_modelsim_tmp'),
    [switch]$sd_equivalence,
    [int]$startup_require_early = 1,
    [int]$startup_sector_delay_cycles = 0
)
$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('tests')) {
    $tests += @('tb_photo_power_reset','tb_photo_flash_stable','tb_photo_startup_subtitle','tb_photo_font_cache','tb_photo_font_ranges','tb_photo_font_startup','tb_photo_wav_faults','tb_photo_wav_missing','tb_photo_audio_history','tb_photo_image_scale','tb_photo_image_scale_full',
        'tb_photo_image_scale_pipeline','tb_photo_image_scale_pipeline_full','tb_photo_image_scale_wav_full',
        'tb_photo_image_scale_cancel','tb_photo_image_scale_faults','tb_photo_image_scale_demo')
}
$sim_root = Join-Path $PSScriptRoot '../sim'
$saved_temp=$env:TEMP
$saved_tmp=$env:TMP
$env:TEMP=$temp_dir
$env:TMP=$env:TEMP
New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
Push-Location $sim_root
try {
    & python -B (Join-Path $PSScriptRoot 'prepare_badge_audio.py')
    if ($LASTEXITCODE -ne 0) { throw 'Audio fixture generation failed' }
    if (-not (Test-Path -LiteralPath 'tf_card/FONT16.BIN')) {
        & python -B (Join-Path $PSScriptRoot 'make_subtitle_font.py')
        if ($LASTEXITCODE -ne 0) { throw 'Indexed font generation failed' }
    }
    & python -B (Join-Path $PSScriptRoot 'make_subtitle_font.py') --fixtures-only
    if ($LASTEXITCODE -ne 0) { throw 'Font regression fixture preparation failed' }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../src/app/photo_font.dath') -Destination 'photo_font.dath' -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../src/app/photo_subtitle_font.dath') -Destination 'photo_subtitle_font.dath' -Force
    if ($tests -contains 'tb_photo_image_scale_demo') {
        & python -B (Join-Path $PSScriptRoot 'prepare_image_scale_demo.py')
        if ($LASTEXITCODE -ne 0) { throw 'Scale demo fixture preparation failed' }
    }
    $library_path = Join-Path 'work/libraries' $library
    New-Item -ItemType Directory -Path 'work/libraries' -Force | Out-Null
    & "$model_bin/vlib.exe" $library_path
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & "$model_bin/vmap.exe" $library $library_path
    if ($LASTEXITCODE -ne 0) { throw 'vmap failed' }
    & "$model_bin/vlog.exe" -sv -work $library ../src/app/*.v legacy/*.v
    if ($LASTEXITCODE -ne 0) { throw 'Application compilation failed' }
    if($sd_equivalence) {
        & "$model_bin/vlog.exe" -sv -work $library reference/sd_spi_byte_reference.v reference/sd_card_reader_reference.v sd_reader_equivalence.sv
        if($LASTEXITCODE -ne 0){throw 'SD equivalence compilation failed'}
    }
    & "$model_bin/vlog.exe" -work $library "$td_root/sim_release/eg4/eg_logic_bram.v" "$td_root/sim_release/eg4/eg_phy_bram.v" "$td_root/sim_release/eg4/eg_phy_bram32k.v" "$td_root/sim_release/eg4/eg_phy_glbl.v"
    if ($LASTEXITCODE -ne 0) { throw 'Official font BRAM model compilation failed' }
    & "$model_bin/vlog.exe" -work $library '+incdir+../src/user_source/hdl_source/SD' ../src/user_source/hdl_source/IP/afifo_32_16_256.v ../src/user_source/hdl_source/SD/color_bar.v ../src/user_source/hdl_source/SD/video_timing_data.v ../src/user_source/hdl_source/SD/video_delay.v ../src/user_source/hdl_source/audio_arc_calculate.v
    if ($LASTEXITCODE -ne 0) { throw 'Official video compilation failed' }
    & "$model_bin/vlog.exe" -work $library '+incdir+../src/user_source/hdl_source/include' '+incdir+../src/td_project' ../src/user_source/hdl_source/include/sdr_as_ram.enc.v ../src/user_source/hdl_source/include/sdr_init_ref.enc.v ../src/user_source/hdl_source/include/sdr_wrrd.enc.v
    if ($LASTEXITCODE -ne 0) { throw 'Official SDRAM compilation failed' }
    & "$model_bin/vlog.exe" -sv -work $library tb_photo_status_osd.sv tb_photo_wav_errors.sv tb_photo_audio_product.sv tb_photo_wav.sv tb_photo_pipeline.sv tb_sd_card.sv tb_sd_reset.sv tb_bmp_edges.sv tb_photo_control.sv tb_photo_badge.sv tb_photo_exam_timer.sv tb_photo_overlay.sv tb_photo_transition.sv photo_sdram_model.sv tb_photo_sdram.sv tb_photo_ten.sv tb_photo_cache.sv tb_photo_audio.sv tb_photo_scene_audio.sv tb_photo_config_flash.sv tb_photo_subtitle.sv
    if ($LASTEXITCODE -ne 0) { throw 'Testbench compilation failed' }
    & "$model_bin/vlog.exe" -sv -work $library tb_photo_audio_history.sv
    if ($LASTEXITCODE -ne 0) { throw 'Audio history testbench compilation failed' }
    & "$model_bin/vlog.exe" -sv -work $library tb_photo_image_scale.sv tb_photo_image_scale_demo.sv
    if ($LASTEXITCODE -ne 0) { throw 'Image scale testbench compilation failed' }
    & "$model_bin/vlog.exe" -sv -work $library tb_photo_startup_subtitle.sv
    if ($LASTEXITCODE -ne 0) { throw 'Startup subtitle testbench compilation failed' }
    $top_source=Get-Content -LiteralPath '../src/app/top.v' -Raw
    $power_reset_logic=[regex]::Match($top_source,'(?s)    reg \[15:0\] startup_reset_buf=.*?(?=    sys_pll sys_pll_m0)')
    $domain_reset_logic=[regex]::Matches($top_source,'(?m)^    photo_reset_sync (?:mem|pix|system)_reset_proc .*?;')
    if(-not $power_reset_logic.Success -or $domain_reset_logic.Count -ne 3){throw 'Production reset fixture extraction failed'}
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'work/photo_power_reset_fixture.vh'),
        $power_reset_logic.Value+($domain_reset_logic.Value -join "`n"))
    & "$model_bin/vlog.exe" -sv -work $library tb_photo_power_reset.sv
    if ($LASTEXITCODE -ne 0) { throw 'Power reset testbench compilation failed' }
    & "$model_bin/vlog.exe" -sv -work $library tb_photo_font_cache.sv tb_photo_font_ranges.sv tb_photo_font_service.sv
    if ($LASTEXITCODE -ne 0) { throw 'Font cache testbench compilation failed' }
    & "$model_bin/vlog.exe" -sv -work $library tb_photo_sd_boot.sv
    if ($LASTEXITCODE -ne 0) { throw 'Actual SPI startup testbench compilation failed' }
    & "$model_bin/vlog.exe" -sv -work $library tb_photo_culture_priority.sv tb_photo_culture_full.sv
    if ($LASTEXITCODE -ne 0) { throw 'Culture manual-priority testbench compilation failed' }
    foreach ($test_name in $tests) {
        if($test_name -eq 'tb_photo_flash_accept') {
            foreach($flash_module in @('photo_config_flash','photo_flash_record')) {
                $flash_fixture=Get-Content -LiteralPath "../src/app/$flash_module.v" -Raw
                $flash_fixture=$flash_fixture.Replace('.start(store_start)', '.start(store_start && tb_photo_config_flash.store_accept_gate)')
                $flash_fixture=$flash_fixture.Replace('.start(byte_start)', '.start(byte_start && tb_photo_config_flash.byte_accept_gate)')
                [IO.File]::WriteAllText((Join-Path (Get-Location) "work/${flash_module}_accept_fixture.v"),$flash_fixture)
                & "$model_bin/vlog.exe" -sv -work $library "work/${flash_module}_accept_fixture.v"
                if($LASTEXITCODE -ne 0){throw 'Flash acceptance fixture compilation failed'}
            }
        }
        if($test_name -eq 'tb_photo_startup_requests') {
            $request_fixture=Get-Content -LiteralPath '../src/app/photo_ingest.v' -Raw
            $request_fixture=$request_fixture.Replace('.start(fs_start)', '.start(fs_start && tb_photo_sd_boot.catalog_gate)')
            $request_fixture=$request_fixture.Replace('.file_req(fs_file_req && state!=st_error)', '.file_req(fs_file_req && state!=st_error && tb_photo_sd_boot.file_gate)')
            $request_fixture=$request_fixture.Replace('.sector_req(card_sector_req)', '.sector_req(card_sector_req && tb_photo_sd_boot.card_gate)')
            [IO.File]::WriteAllText((Join-Path (Get-Location) 'work/photo_ingest_request_fixture.v'),$request_fixture)
            & "$model_bin/vlog.exe" -sv -work $library work/photo_ingest_request_fixture.v
            if($LASTEXITCODE -ne 0){throw 'Startup request fixture compilation failed'}
        }
        $result_name=if($test_name -eq 'tb_photo_font_startup'){'tb_photo_startup_subtitle'}else{$test_name}
        $env:ANLU_SIM_TEST = $test_name
        $env:ANLU_SIM_LIBRARY = $library
        $env:ANLU_SD_EQUIVALENCE=[int][bool]$sd_equivalence
        $env:ANLU_STARTUP_REQUIRE_EARLY = $startup_require_early
        $env:ANLU_STARTUP_SECTOR_DELAY_CYCLES = $startup_sector_delay_cycles
        if (Test-Path -LiteralPath "$result_name.result") { Remove-Item -LiteralPath "$result_name.result" }
        & "$model_bin/vsim.exe" -c -l "$test_name.log" -do run.do
        if ($LASTEXITCODE -ne 0) { throw "$test_name failed" }
        if (-not (Select-String -LiteralPath "$result_name.result" -SimpleMatch "PASS $result_name")) {
            throw "$test_name did not reach its completion check"
        }
        Get-Content -LiteralPath "$result_name.result"
        if($test_name -eq 'tb_photo_flash_accept') {
            & "$model_bin/vlog.exe" -sv -work $library ../src/app/photo_config_flash.v ../src/app/photo_flash_record.v
            if($LASTEXITCODE -ne 0){throw 'Production Flash modules restore failed'}
        }
        if($test_name -eq 'tb_photo_startup_requests') {
            & "$model_bin/vlog.exe" -sv -work $library ../src/app/photo_ingest.v
            if($LASTEXITCODE -ne 0){throw 'Production ingest restore failed'}
        }
        if($sd_equivalence -and -not (Select-String -LiteralPath "$test_name.log" -Pattern 'PASS SD baseline equivalence .*cycles=[1-9][0-9]*')){throw 'SD equivalence did not execute'}
    }
} finally {
    $env:TEMP=$saved_temp
    $env:TMP=$saved_tmp
    Remove-Item Env:ANLU_SIM_TEST -ErrorAction SilentlyContinue
    Remove-Item Env:ANLU_SIM_LIBRARY -ErrorAction SilentlyContinue
    Remove-Item Env:ANLU_SD_EQUIVALENCE -ErrorAction SilentlyContinue
    Remove-Item Env:ANLU_STARTUP_REQUIRE_EARLY -ErrorAction SilentlyContinue
    Remove-Item Env:ANLU_STARTUP_SECTOR_DELAY_CYCLES -ErrorAction SilentlyContinue
    Pop-Location
}
