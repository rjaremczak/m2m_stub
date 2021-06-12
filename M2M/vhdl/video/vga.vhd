-------------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework  
--
-- VGA control block
--
-- This block overlays the On Screen Menu (OSM) on top of the MiSTer Core output.
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2021 and licensed under GPL v3
-------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qnice_tools.all;
use work.video_modes_pkg.all;

entity vga is
   generic  (
      G_VIDEO_MODE         : video_modes_t;
      G_CORE_DX            : natural;
      G_CORE_DY            : natural;
      G_CORE_TO_VGA_SCALE  : natural;
      G_FONT_DX            : natural;
      G_FONT_DY            : natural
   );
   port (
      clk_i                : in  std_logic;
      rstn_i                 : in  std_logic;

      -- OSM configuration from QNICE
      vga_osm_cfg_enable_i : in  std_logic;
      vga_osm_cfg_xy_i     : in  std_logic_vector(15 downto 0);
      vga_osm_cfg_dxdy_i   : in  std_logic_vector(15 downto 0);

      -- OSM interface to VRAM (character RAM and attribute RAM)
      vga_osm_vram_addr_o  : out std_logic_vector(15 downto 0);
      vga_osm_vram_data_i  : in  std_logic_vector(7 downto 0);
      vga_osm_vram_attr_i  : in  std_logic_vector(7 downto 0);

      -- Core interface to VRAM (24-bit RGB colors in the core's native resolution)
      vga_core_vram_addr_o : out std_logic_vector(14 downto 0);
      vga_core_vram_data_i : in  std_logic_vector(23 downto 0);

      -- VGA / VDAC output
      vga_red_o            : out std_logic_vector(7 downto 0);
      vga_green_o          : out std_logic_vector(7 downto 0);
      vga_blue_o           : out std_logic_vector(7 downto 0);
      vga_hs_o             : out std_logic;
      vga_vs_o             : out std_logic;
      vga_de_o             : out std_logic;
      vdac_clk_o           : out std_logic;
      vdac_sync_n_o        : out std_logic;
      vdac_blank_n_o       : out std_logic
   );
end vga;

architecture synthesis of vga is

   -- VGA signals
   signal vga_hs         : std_logic;
   signal vga_vs         : std_logic;
   signal vga_disp_en    : std_logic;
   signal vga_col        : integer range 0 to G_VIDEO_MODE.H_PIXELS - 1;
   signal vga_row        : integer range 0 to G_VIDEO_MODE.V_PIXELS - 1;

   -- Delayed VGA signals
   signal vga_hs_d       : std_logic;
   signal vga_vs_d       : std_logic;
   signal vga_disp_en_d  : std_logic;

   -- Core and OSM pixel data
   signal vga_core_on_d  : std_logic;
   signal vga_core_rgb_d : std_logic_vector(23 downto 0);   -- 23..0 = RGB, 8 bits each
   signal vga_osm_on_d   : std_logic;
   signal vga_osm_rgb_d  : std_logic_vector(23 downto 0);   -- 23..0 = RGB, 8 bits each

begin

   -- Component that produces VGA timings and outputs the currently active pixel coordinate (row, column)
   vga_pixels_and_timing : entity work.vga_controller
      port map (
         h_pulse   => G_VIDEO_MODE.H_PULSE,     -- horizontal sync pulse width in pixels
         h_bp      => G_VIDEO_MODE.H_BP,        -- horizontal back porch width in pixels
         h_pixels  => G_VIDEO_MODE.H_PIXELS,    -- horizontal display width in pixels
         h_fp      => G_VIDEO_MODE.H_FP,        -- horizontal front porch width in pixels
         h_pol     => G_VIDEO_MODE.H_POL,       -- horizontal sync pulse polarity (1 = positive, 0 = negative)
         v_pulse   => G_VIDEO_MODE.V_PULSE,     -- vertical sync pulse width in rows
         v_bp      => G_VIDEO_MODE.V_BP,        -- vertical back porch width in rows
         v_pixels  => G_VIDEO_MODE.V_PIXELS,    -- vertical display width in rows
         v_fp      => G_VIDEO_MODE.V_FP,        -- vertical front porch width in rows
         v_pol     => G_VIDEO_MODE.V_POL,       -- vertical sync pulse polarity (1 = positive, 0 = negative)
   
         pixel_clk => clk_i,       -- pixel clock at frequency of VGA mode being used
         reset_n   => rstn_i,      -- active low asycnchronous reset
         h_sync    => vga_hs,      -- horiztonal sync pulse
         v_sync    => vga_vs,      -- vertical sync pulse
         disp_ena  => vga_disp_en, -- display enable ('1' = display time, '0' = blanking time)
         column    => vga_col,     -- horizontal pixel coordinate
         row       => vga_row,     -- vertical pixel coordinate
         n_blank   => open,        -- direct blacking output to DAC
         n_sync    => open         -- sync-on-green output to DAC
      ); -- vga_pixels_and_timing : entity work.vga_controller


   -----------------------------------------------
   -- Instantiate On-Screen-Menu generator
   -----------------------------------------------

   i_vga_osm : entity work.vga_osm
      generic map (
         G_VGA_DX             => G_VIDEO_MODE.H_PIXELS,
         G_VGA_DY             => G_VIDEO_MODE.V_PIXELS,
         G_FONT_DX            => G_FONT_DX,
         G_FONT_DY            => G_FONT_DY
      )
      port map (
         clk_i                => clk_i,
         vga_col_i            => vga_col,
         vga_row_i            => vga_row,
         vga_osm_cfg_xy_i     => vga_osm_cfg_xy_i,
         vga_osm_cfg_dxdy_i   => vga_osm_cfg_dxdy_i,
         vga_osm_cfg_enable_i => vga_osm_cfg_enable_i,
         vga_osm_vram_addr_o  => vga_osm_vram_addr_o,
         vga_osm_vram_data_i  => vga_osm_vram_data_i,
         vga_osm_vram_attr_i  => vga_osm_vram_attr_i,
         vga_osm_on_o         => vga_osm_on_d,
         vga_osm_rgb_o        => vga_osm_rgb_d
      ); -- i_vga_osm : entity work.vga_osm


   -----------------------------------------------
   -- Instantiate Core Display generator
   -----------------------------------------------

   i_vga_core : entity work.vga_core
      generic map (
         G_VGA_DX               => G_VIDEO_MODE.H_PIXELS,
         G_VGA_DY               => G_VIDEO_MODE.V_PIXELS,
         G_CORE_DX              => G_CORE_DX,
         G_CORE_DY              => G_CORE_DY,
         G_CORE_TO_VGA_SCALE    => G_CORE_TO_VGA_SCALE
      )
      port map (
         -- pixel clock and current position on screen relative to pixel clock      
         clk_i                => clk_i,
         vga_col_i            => vga_col,
         vga_row_i            => vga_row,
         
         -- 24-bit RGB VRAM data input in the core's native resolution
         vga_core_vram_addr_o => vga_core_vram_addr_o,
         vga_core_vram_data_i => vga_core_vram_data_i,
         
         -- scaled 24-bit RGB output for the current col/row
         vga_core_on_o        => vga_core_on_d,
         vga_core_rgb_o       => vga_core_rgb_d
      ); -- i_vga_core : entity work.vga_core


   p_delay : process (clk_i)
   begin
      if rising_edge(clk_i) then
         vga_hs_d      <= vga_hs;
         vga_vs_d      <= vga_vs;
         vga_disp_en_d <= vga_disp_en;
      end if;
   end process p_delay;


   p_video_signal_latches : process (clk_i)
   begin
      if rising_edge(clk_i) then
         -- Default border color
         vga_red_o   <= (others => '0');
         vga_blue_o  <= (others => '0');
         vga_green_o <= (others => '0');

         if vga_disp_en_d then
            -- MiSTer core output
            if vga_core_on_d then
               vga_red_o   <= vga_core_rgb_d(23 downto 16);
               vga_green_o <= vga_core_rgb_d(15 downto 8);
               vga_blue_o  <= vga_core_rgb_d(7 downto 0);
            end if;

            -- On-Screen-Menu (OSM) output
            if vga_osm_on_d then
               vga_red_o   <= vga_osm_rgb_d(23 downto 16);
               vga_green_o <= vga_osm_rgb_d(15 downto 8);
               vga_blue_o  <= vga_osm_rgb_d(7 downto 0);
            end if;
         end if;

         -- VGA horizontal and vertical sync
         vga_hs_o <= vga_hs_d;
         vga_vs_o <= vga_vs_d;
         vga_de_o <= vga_disp_en_d;
      end if;
   end process; -- p_video_signal_latches : process(vga_pixelclk)


   -- make the VDAC output the image
   -- for some reason, the VDAC does not like non-zero values outside the visible window
   -- maybe "vdac_sync_n <= '0';" activates sync-on-green?
   -- TODO: check that
   vdac_sync_n_o  <= '0';
   vdac_blank_n_o <= '1';
   vdac_clk_o     <= not clk_i; -- inverting the clock leads to a sharper signal for some reason

end synthesis;
