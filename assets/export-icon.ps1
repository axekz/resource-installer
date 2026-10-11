#Requires -Version 5.1
# Format conversion only: preserve generated artwork and its transparency.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'axe-gokz.png'))
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$images = New-Object 'System.Collections.Generic.List[byte[]]'
try {
    if ($source.GetPixel(0, 0).A -ne 0) { throw 'Icon background must be transparent' }
    foreach ($size in $sizes) {
        $bitmap = New-Object Drawing.Bitmap($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.DrawImage($source, 0, 0, $size, $size)
        $stream = New-Object IO.MemoryStream
        $dib = New-Object IO.BinaryWriter($stream)
        try {
            # Encode 32-bit BGRA DIB directly: Icon.Save quantizes to 16 colors.
            $maskStride = [int]([Math]::Ceiling($size / 32.0) * 4)
            $dib.Write([uint32]40); $dib.Write([int32]$size); $dib.Write([int32]($size * 2))
            $dib.Write([uint16]1); $dib.Write([uint16]32); $dib.Write([uint32]0)
            $dib.Write([uint32]($size * $size * 4 + $maskStride * $size))
            1..4 | ForEach-Object { $dib.Write([uint32]0) }
            $mask = New-Object byte[] ($maskStride * $size)
            for ($y = $size - 1; $y -ge 0; $y--) {
                for ($x = 0; $x -lt $size; $x++) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    $dib.Write([byte]$pixel.B); $dib.Write([byte]$pixel.G)
                    $dib.Write([byte]$pixel.R); $dib.Write([byte]$pixel.A)
                    if ($pixel.A -eq 0) {
                        $index = ($size - 1 - $y) * $maskStride + [int][Math]::Floor($x / 8.0)
                        $mask[$index] = $mask[$index] -bor (128 -shr ($x % 8))
                    }
                }
            }
            $dib.Write($mask); $dib.Flush()
            $images.Add($stream.ToArray())
        } finally {
            $dib.Dispose(); $stream.Dispose()
            $graphics.Dispose(); $bitmap.Dispose()
        }
    }
} finally { $source.Dispose() }
$file = [IO.File]::Create((Join-Path $PSScriptRoot 'axe-gokz.ico'))
$writer = New-Object IO.BinaryWriter($file)
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
    [uint32]$offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$images[$i].Length); $writer.Write($offset)
        $offset += $images[$i].Length
    }
    foreach ($data in $images) { $writer.Write($data) }
} finally { $writer.Dispose() }
