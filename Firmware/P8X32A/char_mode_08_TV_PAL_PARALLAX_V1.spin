{

40 x 24 text display driver TV portion    Rev 01

PAL reference test for Briel Replica 1 TE.
Low-level PAL timing follows Parallax TV.spin v1.1 PAL metrics:
  fPAL=4_433_618, line=4540 PLLA clocks, sync=848 clocks,
  vvis=286, vinv=18, vrep=5.
The TE screen/font interface and character rendering loop are retained.
Active character colors are stripped to luminance-only (monochrome).

Right now, two text sizes are possible.  320 pixels will yield 40x24 text
                                         160 pixels will yield 20x24 text

                                         change the CHOOSE_horizontal_pixels value below

                                         Vertical size and color phase work in progress....

Doug Dingus 09/07



            ********************************************************
            ** IMPORTANT NOTE:  This version of "char_mode_08_TV" **
            ** is configured for demoboard/protoboard video       **
            ** settings.  Obtain a copy of the original zip for   **
            ** Hydra compatibility  --JEFF--                      **
            ********************************************************

}



CON
 
  
PUB start(tvpointer) | i, j, k

  cognew(@entry,tvpointer)
  

DAT                     org
entry                   jmp     #initialization         'Jump past the constants



CON  PAL_color_frequency        =     4_433_618
DAT  PAL_color_freq             long  PAL_color_frequency

' Exact PAL metrics from Parallax TV.spin v1.1
CON  PAL_line_clocks            =     4540
CON  PAL_hsync_clocks           =      848
CON  PAL_active_video_clocks    =     PAL_line_clocks - PAL_hsync_clocks    '3692

DAT  PAL_hsync_VSCL             long  217936     '(53 << 12) + 848
DAT  PAL_vsync_second_VSCL      long  325006     '(79 << 12) + 1422
DAT  PAL_halfline_VSCL          long  2270       '4540 / 2
DAT  PAL_active_video_VSCL      long  PAL_active_video_clocks
DAT  PAL_control_signal_palette long  $00_00_02_AA

'***************************************************
'* User graphics lines                             *
'***************************************************
CON CHOOSE_horizontal_pixels      = 320
CON CHOOSE_vertical_pixel_height  = 0

' The PAL test which looked sharper used 10 PLLA clocks per text pixel.
' 320 * 10 = 3200 clocks, leaving 492 clocks for the two horizontal porches.
CON CHOOSE_clocks_per_gfx_pixel   = 10
CON CALC_bytes_per_line           = CHOOSE_horizontal_pixels / 8
CON CALC_waitvids                 = CALC_bytes_per_line
CON CALC_clocks_per_gfx_frame     = CHOOSE_clocks_per_gfx_pixel * 8
DAT CALC_user_data_VSCL           long (CHOOSE_clocks_per_gfx_pixel << 12) + CALC_clocks_per_gfx_frame
CON CALC_frames_per_gfx_line      = CHOOSE_horizontal_pixels / 8

CON CALC_overscan                 = PAL_active_video_clocks - (CHOOSE_horizontal_pixels * CHOOSE_clocks_per_gfx_pixel) '492
CON CHOOSE_horizontal_offset      = 0
CON CALC_backporch                = (CALC_overscan / 2) + CHOOSE_horizontal_offset '246
CON CALC_frontporch               = CALC_overscan - CALC_backporch                 '246

DAT

' Video hardware setup



initialization          'set up VCFG

                        ' VCFG: setup Video Configuration register and 3-bit tv DAC pins to output
                        movs    VCFG, #%0111_0000       ' VCFG'S = pinmask (pin31: 0000_0111 : pin24)
                        movd    VCFG, #1                ' VCFG'D = pingroup (grp. 3 i.e. pins 24-31)

                        movi    VCFG, #%0_11_111_000
                                

                                                        ' baseband video on bottom nibble, 2-bit color, enable chroma on broadcast & baseband
                                                        ' %0_xx_x_x_x_xxx : Not used
                                                        ' %x_10_x_x_x_xxx : Composite video to top nibble, broadcast to bottom nibble
                                                        ' %x_xx_1_x_x_xxx : 4 color mode
                                                        ' %x_xx_x_1_x_xxx : Enable chroma on broadcast
                                                        ' %x_xx_x_x_1_xxx : Enable chroma on baseband
                                                        ' %x_xx_x_x_x_000 : Broadcast Aural FM bits (don't care)

                        or      DIRA, tvport_mask       ' set DAC pins to output

                        ' 
                        'or      DIRA, #1                ' enable debug LED
                        'mov     OUTA, #1                ' light up debug LED

                        ' CTRA: setup Frequency to Drive Video
                        movi    CTRA,#%00001_111        ' pll internal routed to Video, PHSx+=FRQx (mode 1) + pll(16x)
                        mov     r1, PAL_color_freq     ' r1: PAL colour frequency in Hz (4.433618MHz)
                        rdlong  v_clkfreq, #0           ' copy clk frequency. (80Mhz)
                        mov     r2, v_clkfreq           ' r2: CLKFREQ (80MHz)
                        call    #dividefract            ' perform r3 = 2^32 * r1 / r2
                        mov     v_freq, r3              ' v_freq now contains frqa.       (191)
                        mov     FRQA, r3                ' set frequency for counter


'get parameters from parameter block, and pass them to COG code here

                        mov     C, PAR                 ' get parameter block address
                        rdlong  A, C                   ' get screen address
                        mov     bmp, A                 ' store another copy
                        
                        add     C, #4                  'index to fonttab address
                        rdlong  fonttab, C             'store it 

                        add     C, #4                   'index to mode value
                        rdlong  pixel_mode, C           'store it 

                        add     C, #4                  'index to colors value
                        rdlong  colors, C              'store them...
                        mov     fat_mode, colors         'preserve original value for mode detection
                        and     colors, mono_color_mask  'PAL text is luma-only: $0E0A -> $0602
                        mov     phaseflip, #0            'PAL burst phase state

'-----------------------------------------------------------------------------
                        ' PAL frame:
                        '   18 invisible + 47 visible top blank lines
                        '   192 active text lines
                        '   47 visible bottom blank lines
                        '   5+5+5 half-line vertical sync groups + final half-line
                        ' Total = 312 PAL lines (progressive-style 50 Hz frame).
frame_loop
                        mov     line_loop, #65

:vert_back_porch        call    #pal_hsync
                        mov     VSCL, PAL_active_video_VSCL
                        waitvid black_border, #0
                        djnz    line_loop, #:vert_back_porch
'-----------------------------------------------------------------------------

                        mov     line_loop, #192
                        mov     fontline, #0

user_graphics_lines     call    #pal_hsync

                        mov     VSCL, #CALC_backporch
                        waitvid black_border, #0

                        mov     VSCL, CALC_user_data_VSCL
                        movi    VCFG, #%0_11_011_000     '2-color active text
                        mov     r1, #CALC_waitvids

                        mov     fontsum, fonttab
                        add     fontsum, fontline

                        tjz     fat_mode, #fat_bit_mode

:draw_pixels            rdbyte  B, A
                        shl     B, #3
                        add     B, fontsum
                        rdbyte  C, B
                        waitvid colors, C
                        add     A, #1
                        djnz    r1, #:draw_pixels
                        jmp     #end_of_flag_line

fat_bit_mode            rdlong  B, A
                        mov     colors, B
                        shr     B, #24
                        shl     B, #3
                        add     B, fontsum
                        rdbyte  C, B
                        and     colors, color_mask
                        and     colors, mono_color_mask  'strip chroma in 16-bit mode too
                        waitvid colors, C
                        add     A, #4
                        djnz    r1, #fat_bit_mode

end_of_flag_line        mov     VSCL, #CALC_frontporch
                        waitvid black_border, #0
                        movi    VCFG, #%0_11_111_000     '4-color for PAL sync

                        tjz     fat_mode, #fat_offset

                        add     fontline, #1
                        and     fontline, #%0111 wz
                if_nz   sub     A, #CALC_bytes_per_line
                        jmp     #frame_draw

fat_offset              add     fontline, #1
                        and     fontline, #%0111 wz
                if_nz   sub     A, #CALC_bytes_per_line*4

frame_draw              djnz    line_loop, #user_graphics_lines

                        mov     A, bmp

                        mov     line_loop, #47
vert_front_porch        call    #pal_hsync
                        mov     VSCL, PAL_active_video_VSCL
                        waitvid black_border, #0
                        djnz    line_loop, #vert_front_porch

'-----------------------------------------------------------------------------
                        ' PAL vertical sync copied structurally from Parallax TV.spin:
                        ' five high half-lines, five low half-lines, five high
                        ' half-lines, then the final half line.

                        mov     line_loop, #5
:vsync_higha            mov     VSCL, PAL_hsync_VSCL
                        waitvid PAL_control_signal_palette, pal_sync_high1
                        mov     VSCL, PAL_vsync_second_VSCL
                        waitvid PAL_control_signal_palette, pal_sync_high2
                        djnz    line_loop, #:vsync_higha

                        mov     line_loop, #5
:vsync_low              mov     VSCL, PAL_hsync_VSCL
                        waitvid PAL_control_signal_palette, pal_sync_low1
                        mov     VSCL, PAL_vsync_second_VSCL
                        waitvid PAL_control_signal_palette, pal_sync_low2
                        djnz    line_loop, #:vsync_low

                        mov     line_loop, #5
:vsync_highb            mov     VSCL, PAL_hsync_VSCL
                        waitvid PAL_control_signal_palette, pal_sync_high1
                        mov     VSCL, PAL_vsync_second_VSCL
                        waitvid PAL_control_signal_palette, pal_sync_high2
                        djnz    line_loop, #:vsync_highb

                        mov     VSCL, PAL_halfline_VSCL
                        waitvid PAL_control_signal_palette, pal_sync_high2

                        jmp     #frame_loop

'-----------------------------------------------------------------------------
' PAL horizontal sync.
' On PAL, the burst phase alternates every normal scanline.
pal_hsync               xor     phaseflip, phasemask
                        mov     r0, phaseflip
                        xor     r0, PAL_control_signal_palette
                        mov     VSCL, PAL_hsync_VSCL
                        waitvid r0, pal_sync_normal
pal_hsync_ret           ret

' General Purpose Registers
r0                      long                    $0    ' should typically equal 0
r1                      long                    $0
r2                      long                    $0
r3                      long                    $0
phaseflip               long                    $00000000
phasemask               long                    $F0F0F0F0

A                       long                    $0  'coupla more general purpose registers
B                       long                    $0
C                       long                    $0  

bmp                     long                    $0  'tvpointer ends up here 


pixel_mode              long                    $0  'unimplemented...
'the plan here is upper word being vertical height, lower being horizontal pixels per line



colors                  long                    $0000ddda     'default, if not set by calling program
chars                   long                    $0 
fontline                long                    $0   'scanline counter
fonttab                 long                    $0   'HUB memory address of font table
fat_mode                long                    $1   'two color by default

fontsum                long                    $0   'this is fontline + fonttab

color_mask              long                    $0000ffff
mono_color_mask         long                    $00000707


' Video (TV) Registers
tvport_mask             long                    %0000_1111<<12

v_freq                  long                    0

' Graphics related vars.
v_coffset               long                    $02020202  ' color offset (every color is added by $02)
v_clkfreq               long                    $0

' /////////////////////////////////////////////////////////////////////////////
' dividefract:
' Perform 2^32 * r1/r2, result stored in r3 (useful for TV calc)
' This is taken from the tv driver.
' NOTE: It divides a bottom heavy fraction e.g. 1/2 and gives the result as a 32-bit fraction.
' /////////////////////////////////////////////////////////////////////////////
dividefract                                     
                        mov     r0,#32+1
:loop                   cmpsub  r1,r2           wc
                        rcl     r3,#1
                        shl     r1,#1
                        djnz    r0,#:loop

dividefract_ret         ret                             '+140


'Pixel streams
' Exact PAL sync patterns from Parallax TV.spin v1.1.
pal_sync_normal         long    %010101_00000000_01_101010101010_0101
pal_sync_high1          long    %0101010101010101010101_101010_0101
pal_sync_high2          long    %01010101010101010101010101010101
pal_sync_low1           long    %1010101010101010101010101010_0101
pal_sync_low2           long    %01_101010101010101010101010101010
all_black               long    %01010101010101010101010101010101
border                  long    0

' Some unimportant irrelevant constants for generating demo user display etc.
line_loop               long    0
tile_loop               long    0


' Overscan color choices --need to set these as parameters
'  These are always 4 colors (or blanking level) stored in reverse order:
'                               Color3_Color2_Color1_Color0

black_border             long    $02020202
blue_border_in_color0    long    $02020202
green_border_in_color0   long    $02020202
magenta_border_in_color0 long    $02020202
brown_border_in_color0   long    $02020202



                        