param(
    [string]$output_dir = (Join-Path $PSScriptRoot '../sim/tf_card'),
    [int]$image_count = 10,
    [int[]]$bad_indices = @(2, 7)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Path $output_dir -Force | Out-Null
$font = [System.Drawing.Font]::new('Consolas', 22)
$colors = @('Red', 'Lime', 'Blue', 'Cyan', 'Magenta', 'Yellow', 'White', 'Gray')
try {
    foreach ($image_index in 1..$image_count) {
        $image = [System.Drawing.Bitmap]::new(640, 480, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $canvas = [System.Drawing.Graphics]::FromImage($image)
        try {
            $canvas.Clear([System.Drawing.Color]::Black)
            foreach ($band_index in 0..7) {
                $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromName($colors[($band_index + $image_index - 1) % 8]))
                $canvas.FillRectangle($brush, $band_index * 80, 100, 80, 280)
                $brush.Dispose()
            }
            $canvas.DrawRectangle([System.Drawing.Pens]::White, 0, 0, 639, 479)
            $canvas.DrawRectangle([System.Drawing.Pens]::White, 5, 5, 629, 469)
            $canvas.DrawString("PIC$image_index   TOP LEFT", $font, [System.Drawing.Brushes]::White, 18, 20)
            $canvas.DrawString('640 x 480 / BMP24', $font, [System.Drawing.Brushes]::White, 18, 58)
            $canvas.DrawString('BOTTOM RIGHT   R G B', $font, [System.Drawing.Brushes]::White, 210, 420)
            $image.Save((Join-Path $output_dir "PIC$image_index.BMP"), [System.Drawing.Imaging.ImageFormat]::Bmp)
        } finally {
            $canvas.Dispose()
            $image.Dispose()
        }
    }
    foreach ($image_index in $bad_indices) {
        $image_path = Join-Path $output_dir "PIC$image_index.BMP"
        $image_bytes = [System.IO.File]::ReadAllBytes($image_path)
        $bad_length = if ($image_index -eq $bad_indices[0]) { 4 * 1024 * 1024 } else { 64 }
        $bad_bytes = [byte[]]::new($bad_length)
        [Array]::Copy($image_bytes, $bad_bytes, [Math]::Min($bad_length, $image_bytes.Length))
        [Array]::Copy([BitConverter]::GetBytes([int]$bad_length), 0, $bad_bytes, 2, 4)
        $bad_bytes[30] = 1
        [System.IO.File]::WriteAllBytes($image_path, $bad_bytes)
    }
} finally { $font.Dispose() }
Get-ChildItem -LiteralPath $output_dir -Filter 'PIC*.BMP' | Select-Object Name, Length
