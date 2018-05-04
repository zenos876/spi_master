/*
 * Data Format
 *   bit 15-12: SPI Command sets 
 *     4'b0000: Read from SPI 8-bit Data Register
 *     4'b0010: Read from SPI 8-bit Data Register and 
 *              Assert a Read Command from the same Address
 *     4'b0011: Read from SPI 8-bit Data Register and
 *              Assert a Read Command from (Address Register + 1)
 *     4'b0100: Read from SPI 12-bit Address Register 
 *
 *     4'b1000: Write to SPI 8-bit Data Register 
 *     4'b1010: Write to SPI 8-bit Data Register and 
 *              Assert a Write Command 
 *     4'b1011: Write to SPI 8-bit Data Register and
 *              Assert a Write Command and then
 *              Increase Address Register by 1
 *     4'b1100: Write to SPI 12-bit Address Register 
 *     4'b1101: Write to SPI 12-bit Address Register and 
 *              Prepare data in SPI 8-bit Data Register
 *   bit 11-0: Data/Address Field 
 */

`timescale 1ns / 10ps

module spi_slv_8b8b(
  input             spi_clk,
  input             spi_en_n, 
  input             spi_mosi,
  output reg        spi_miso = 1'b0,		//输出到主机数据信号为0

  input             clk,
  input             rst_b, 

  output reg        wr_en = 1'b0,
  output reg        rd_en = 1'b0,
  output reg [11:0] adr,
  output reg  [7:0] dout,
  input       [7:0] din
);

  // SPI<-->clk clock sync signals
  reg     [2:0] spi_clk_sync  = 3'd7, 
                spi_en_n_sync = 3'd0, 
                spi_mosi_sync = 3'd0;
  wire          spi_clk_rise, spi_clk_rise_1,
                spi_clk_fall, spi_clk_fall_1,
                spi_en_n_rise, spi_en_n_fall;

  // clk clock domain signals
  reg     [2:0] fsm_cs, fsm_ns;
  reg     [4:0] shin_cntr = 'd17;
  reg    [15:0] shin_reg;
  reg    [11:0] shout_reg;
  //reg           wr_cmd, rd_cmd;
  reg     [1:0] cmd_hit = 2'd0, 
                ad_hit  = 2'd0;
  reg     [1:0] adr_inc = 2'd0; 
  reg     [3:0] spi_cmd;
  
  // SPI<-->clk clock sync logic
  assign spi_clk_rise   = ~spi_clk_sync[1]  &  spi_clk_sync[0];		//clk后进;	
  assign spi_clk_rise_1 = ~spi_clk_sync[2]  &  spi_clk_sync[1];		//clk先进;
  assign spi_clk_fall   =  spi_clk_sync[1]  & ~spi_clk_sync[0];
  assign spi_clk_fall_1 =  spi_clk_sync[2]  & ~spi_clk_sync[1];
  assign spi_en_n_rise  = ~spi_en_n_sync[1] &  spi_en_n_sync[0] & (fsm_cs == 'd1);
  assign spi_en_n_fall  =  spi_en_n_sync[1] & ~spi_en_n_sync[0];

  always @(posedge clk or negedge rst_b)
  begin
    if (!rst_b)
    begin
      spi_clk_sync  <= 3'd7;
      spi_en_n_sync <= 3'd0;
      spi_mosi_sync <= 3'd0;
    end
    else
    begin   
      spi_clk_sync  <= {spi_clk_sync,  spi_clk};
      spi_en_n_sync <= {spi_en_n_sync, spi_en_n};
      spi_mosi_sync <= {spi_mosi_sync, spi_mosi};
    end
  end

  // clk clock domain logics
  always @(posedge clk or negedge rst_b)
  begin: SPI_FSM_seq
    if (!rst_b)
      fsm_cs <= 'd0;
    else
      fsm_cs <= fsm_ns;
  end

  always @(*)
  begin : FSM_Next
    case (fsm_cs)
    'd1:
      fsm_ns = (spi_en_n_rise)? 'd0:'d1;		//判断CS高电平时 状态为0；CS低电平时 状态为1

    default: // 'd0;
      fsm_ns = (spi_en_n_fall)? 'd1:'d0;
    endcase
  end

  always @(posedge clk or negedge rst_b)
  begin
    if (!rst_b)
    begin
      cmd_hit <= 'd0;		//2'b
      ad_hit  <= 'd0;		//2'b
      spi_cmd <= 4'hF;      //4'b1111
      shin_cntr <= 'd17;	//5'b10001
      spi_miso <= 1'b0;
      shout_reg <= 'd0;		//12'b
    end
    else
    begin
      cmd_hit[1] <= cmd_hit[0];
      cmd_hit[0] <= spi_clk_rise_1 & (shin_cntr == 'd13);
      ad_hit <= spi_clk_rise_1 & (shin_cntr == 'd1);
      if (fsm_cs == 'd0)
        shin_cntr <= 'd17;
      else if (spi_clk_rise)	//cs为低电平  spi_clk_rise = 1
        shin_cntr <= shin_cntr + {5{|shin_cntr}};			//	10000 = 10001+11111		//	{3{0}}重复操作符    结果为3'b000
      
      if (fsm_cs == 'd1 & spi_clk_rise & |shin_cntr)
        shin_reg <= {shin_reg, spi_mosi_sync[1]};

      if (cmd_hit[1] & ~spi_cmd[3])
      begin
        spi_miso <= 1'b0;
        shout_reg <= {4'd0, dout};
      end
      else if (fsm_cs == 'd1 & spi_clk_fall & |shin_cntr)
        {spi_miso, shout_reg} <= {shout_reg, 1'b0};                              
       
      spi_cmd  <= (cmd_hit[0])? shin_reg[3:0]:spi_cmd;   
    end                                                  
  end                                                    
    
  always @(posedge clk or negedge rst_b)                                         
  begin                                                                          
    if (!rst_b)                                                                  
    begin                                                                        
      {wr_en, rd_en} <= 'd0;                                                     
      adr_inc <= 2'd0;                                                           
    end                                                                          
    else                                                                         
    begin                                                                        
      wr_en <= 1'b0;                                                             
      rd_en <= 1'b0;
      adr_inc <= {adr_inc[0], 1'b0};

      if (ad_hit) 
      begin
        case (spi_cmd)
        4'b0010:				//Read from SPI 8-bit Data Register and Assert a Read Command from the same Address
          rd_en <= 1'b1;                                 						   
        4'b0011:                //Read from SPI 8-bit Data Register and Assert a Read Command from (Address Register + 1)                        						   
        begin                                        						   
          rd_en <= 1'b1;                               						   
          adr <= adr + 1'b1;                           						   
        end                                            						   
         
        4'b1000:                //Write to SPI 8-bit Data Register                       						   
          dout <= shin_reg;                            						   
        4'b1010:                //Write to SPI 8-bit Data Register and Assert a Write Command                       						   
        begin                                           						   
          wr_en <= 1'b1;                               						   
          dout <= shin_reg;                            						   
        end                                            						   
        4'b1011:                //Write to SPI 8-bit Data Register and Assert a Write Command and then                      						   
        begin                   //Increase Address Register by 1                       						   
          wr_en <= 1'b1;        
          dout <= shin_reg;     
          adr_inc[0] <= 1'b1;   
        end                     
        4'b1100:                //Write to SPI 12-bit Address Register
          adr <= shin_reg;      
        4'b1101:                //Write to SPI 12-bit Address Register and Prepare data in SPI 8-bit Data Register
        begin                   
          rd_en <= 1'b1;        
          adr <= shin_reg;      
        end                     
        default: 
          ;
        endcase
      end
      else
      begin
        if (adr_inc[1])
          adr <= adr + 1'b1; 
        if (rd_en)
          dout <= din;
      end
    end
  end
endmodule
