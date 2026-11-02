onerror {quit -code 1 -f}
transcript on
set test_top $env(ANLU_SIM_TEST)
set test_library work
if {[info exists env(ANLU_SIM_LIBRARY)]} {set test_library $env(ANLU_SIM_LIBRARY)}
set test_args {}
if {$test_top eq "tb_photo_flash_stable"} {
    set test_top tb_photo_config_flash
    set test_args {-gstable_delay_test=1 -gflash_spi_div=8}
} elseif {$test_top eq "tb_photo_flash_production"} {
    set test_top tb_photo_config_flash
    set test_args {-gflash_spi_div=8}
} elseif {$test_top eq "tb_photo_flash_accept"} {
    set test_top tb_photo_config_flash
    set test_args {-gaccept_delays=1}
} elseif {$test_top eq "tb_photo_startup_requests"} {
    set test_top tb_photo_sd_boot
    set test_args {-gaccept_delays=1}
} elseif {$test_top eq "tb_photo_font_missing"} {
    set test_top tb_photo_font_service
    set test_args {-gmissing_font=1}
} elseif {$test_top eq "tb_photo_font_startup"} {
    set test_top tb_photo_startup_subtitle
    set test_args {-gfont_cache_value=1}
} elseif {$test_top eq "tb_photo_startup_subtitle"} {
    set test_args [list -grequire_early=$env(ANLU_STARTUP_REQUIRE_EARLY) -gsector_delay_cycles=$env(ANLU_STARTUP_SECTOR_DELAY_CYCLES)]
} elseif {$test_top eq "tb_photo_image_scale_cancel"} {
    set test_top tb_photo_ten
    set test_args {-gimage_scale_value=2 -ggroup_prefetch_value=1 -gmanual_priority_value=1}
} elseif {$test_top eq "tb_photo_image_scale_faults"} {
    set test_top tb_photo_ten
    set test_args {-gimage_scale_value=3 -ggroup_prefetch_value=1}
} elseif {$test_top eq "tb_photo_image_scale_pipeline"} {
    set test_top tb_photo_ten
    set test_args {-gimage_scale_value=1 -ggroup_prefetch_value=1}
} elseif {$test_top eq "tb_photo_image_scale_pipeline_full"} {
    set test_top tb_photo_ten
    set test_args {-gimage_scale_value=1 -ggroup_prefetch_value=1 -gfull_size=1}
} elseif {$test_top eq "tb_photo_image_scale_wav_full"} {
    set test_top tb_photo_ten
    set test_args {-gimage_scale_value=1 -ggroup_prefetch_value=1 -gfull_size=1 -gsubtitle_value=1 -gwav_value=1}
} elseif {$test_top eq "tb_photo_image_scale_full"} {
    set test_top tb_photo_image_scale
    set test_args {-gfull_size=1}
} elseif {$test_top eq "tb_photo_wav_faults"} {
    set test_top tb_photo_wav
    set test_args {-gfault_mode=1}
} elseif {$test_top eq "tb_photo_wav_missing"} {
    set test_top tb_photo_wav
    set test_args {-gfault_mode=2}
} elseif {$test_top eq "tb_photo_wav_full"} {
    set test_top tb_photo_ten
    set test_args {-gfull_size=1 -ggroup_prefetch_value=1 -gsubtitle_value=1 -gwav_value=1}
} elseif {$test_top eq "tb_photo_subtitle_manual"} {
    set test_top tb_photo_ten
    set test_args {-ggroup_prefetch_value=1 -gmanual_priority_value=1 -gsubtitle_service_value=1}
} elseif {$test_top eq "tb_photo_subtitle_full"} {
    set test_top tb_photo_ten
    set test_args {-gfull_size=1 -ggroup_prefetch_value=1 -gsubtitle_value=1}
} elseif {[regexp {^tb_photo_subtitle_fat_([123])$} $test_top match mode]} {
    set test_top tb_photo_ten
    set test_args [list -ggroup_prefetch_value=1 -gsubtitle_value=$mode]
} elseif {$test_top eq "tb_photo_manual_priority_full"} {
    set test_top tb_photo_ten
    set test_args {-gfull_size=1 -ggroup_prefetch_value=1 -gmanual_priority_value=1}
} elseif {[regexp {^tb_photo_manual_priority_([012])$} $test_top match mode]} {
    set test_top tb_photo_ten
    set test_args [list -ggroup_prefetch_value=1 -gmanual_priority_value=1 -gtransition_mode_value=$mode]
} elseif {[regexp {^tb_photo_scene_switch_([012])$} $test_top match mode]} {
    set test_top tb_photo_ten
    set test_args [list -gbadge_return=1 -gscene_switch_value=1 -gtransition_mode_value=$mode]
} elseif {$test_top eq "tb_photo_cache_group"} {
    set test_top tb_photo_cache
    set test_args {-ggroup_prefetch=1}
} elseif {$test_top eq "tb_photo_exam_return_full"} {
    set test_top tb_photo_ten
    set test_args {-gfull_size=1 -gscene_audio=1 -gbadge_return=1}
} elseif {$test_top eq "tb_photo_exam_return"} {
    set test_top tb_photo_ten
    set test_args {-gscene_audio=1 -gbadge_return=1}
} elseif {$test_top eq "tb_photo_ten_scene_full"} {
    set test_top tb_photo_ten
    set test_args {-gfull_size=1 -gscene_audio=1}
} elseif {$test_top eq "tb_photo_ten_scene"} {
    set test_top tb_photo_ten
    set test_args {-gscene_audio=1}
} elseif {$test_top eq "tb_photo_ten_full"} {
    set test_top tb_photo_ten
    set test_args {-gfull_size=1}
} elseif {$test_top eq "tb_photo_ten_transition_full_fade"} {
    set test_top tb_photo_ten
    set test_args {-gfull_size=1 -gtransition_mode_value=1}
} elseif {$test_top eq "tb_photo_ten_transition_full_wipe"} {
    set test_top tb_photo_ten
    set test_args {-gfull_size=1 -gtransition_mode_value=2}
} elseif {$test_top eq "tb_photo_group_full"} {
    set test_top tb_photo_ten
    set test_args {-gfull_size=1 -ggroup_prefetch_value=1}
} elseif {$test_top eq "tb_photo_group"} {
    set test_top tb_photo_ten
    set test_args {-ggroup_prefetch_value=1}
} elseif {$test_top eq "tb_photo_audio_ten"} {
    set test_top tb_photo_audio
    set test_args {-gimage_count=10}
} elseif {$test_top eq "tb_sd_reset_full"} {
    set test_top tb_sd_reset
    set test_args {-gfull_rate=1}
} elseif {$test_top eq "tb_photo_ten_bad_first"} {
    set test_top tb_photo_ten
    set test_args {-gbad_first=1}
} elseif {$test_top eq "tb_photo_ten_all_bad"} {
    set test_top tb_photo_ten
    set test_args {-gall_bad=1}
}
set extra_tops {}
if {[info exists env(ANLU_SD_EQUIVALENCE)] && $env(ANLU_SD_EQUIVALENCE)} {
    lappend extra_tops ${test_library}.sd_reader_equivalence_bind
}
vsim -onfinish exit -displaymsgmode tran -msgmode tran {*}$test_args ${test_library}.$test_top ${test_library}.glbl {*}$extra_tops
transcript on
run -all
quit -code 1 -f
