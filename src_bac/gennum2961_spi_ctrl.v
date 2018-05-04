module gennum2961_spi_ctrl
(
  input         clk,  //system clock
  input         rst_b,
  input         stat_poll,
  
  output reg    spi_cs,
  output reg    spi_sck,
  output reg    spi_mosi,
  input         spi_miso,
  
  output [31:0] vid_std,
  output [15:0] raster1,
  output [15:0] raster2,
  output [15:0] raster3,
  output [15:0] raster4
);

parameter  SPI_CLK_DIV = 20;

//register addresses
//localparam REG_VIDEO_FORMAT_352_A_1 = 12'h008,//12'h019,
//           REG_VIDEO_FORMAT_352_B_1 = 12'h009;//12'h01a;

//localparam CMD_VIDEO_FORMAT_A = {1'b1, 3'b0, REG_VIDEO_FORMAT_352_A_1},
//           CMD_VIDEO_FORMAT_B = {1'b1, 3'b0, REG_VIDEO_FORMAT_352_B_1};
           
localparam ST_IDLE          = 0,
           ST_READ_REG      = 1,
           ST_READ_REG_WAIT = 2;
           //ST_READ_VIDEO_FORMAT_B      = 3,
           //ST_READ_VIDEO_FORMAT_B_WAIT = 4;
           
localparam ST_SPI_IDLE      = 0,
           ST_SPI_WRITE_CMD = 1,
           ST_SPI_READ_WAIT = 2,
           ST_SPI_READ_STAT = 3,
           ST_SPI_CMD_GAP   = 4;
           
localparam READ_WAIT_TIME = 5, //in bit time
           CMD_GAP_TIME   = 10;
           
localparam REG_RD_CNT = 6;

reg   [2:0] state;  //state machine variable
reg   [2:0] spi_state;

wire [11:0] REG_ADDR[0:REG_RD_CNT-1];
reg  [15:0] reg_read_data[0:REG_RD_CNT-1];

reg         spi_master_wren_i;
reg  [15:0] spi_master_di_i;
wire        spi_master_wr_ack_o;
wire        spi_master_do_valid_o;
wire [15:0] spi_master_do_o;
reg  [15:0] vid_std_lower, vid_std_upper;
reg         spi_clk_falling, spi_clk_rising;
reg         spi_sck_d1;
reg         spi_clk_enable;
reg  [15:0] spi_read_cmd, spi_read_data;
reg  [11:0] spi_read_addr;
reg         spi_read_req, spi_busy, spi_reading;
reg         spi_sck_int;
reg   [7:0] spi_clk_cnt;
reg   [3:0] spi_bit_cnt;
reg   [3:0] reg_index;

assign REG_ADDR[0] = 12'h01f;
assign REG_ADDR[1] = 12'h020;
assign REG_ADDR[2] = 12'h021;
assign REG_ADDR[3] = 12'h022;
assign REG_ADDR[4] = 12'h006;
assign REG_ADDR[5] = 12'h007;

assign raster1 = reg_read_data[0];
assign raster2 = reg_read_data[1];
assign raster3 = reg_read_data[2];
assign raster4 = reg_read_data[3];

//assign spi_sck = spi_sck_int & spi_clk_enable;
assign vid_std = {reg_read_data[5], reg_read_data[4]};

always @(posedge clk) begin: spi_clk_blk
    spi_sck <= spi_sck_int & spi_clk_enable;
    
    spi_clk_falling <= (~spi_sck_int & spi_sck_d1);
    spi_clk_rising  <= (spi_sck_int & ~spi_sck_d1);
    spi_sck_d1 <= spi_sck_int;
    
    if (spi_clk_cnt < SPI_CLK_DIV / 2 - 1)
        spi_clk_cnt <= spi_clk_cnt + 1;
    else begin
        spi_clk_cnt <= 0;
        spi_sck_int <= ~spi_sck_int;
    end
end

always @(posedge clk) begin: sequencer_blk
    if (~rst_b) begin
        state <= ST_IDLE;
        spi_read_req <= 1'b0;
        reg_index <= 0;
    end
    else begin
        case(state)
            ST_READ_REG: begin
                if (spi_busy) begin
                    state <= ST_READ_REG_WAIT;
                    spi_read_req <= 1'b0;
                end
            end
            
            ST_READ_REG_WAIT: begin
                if (~spi_busy) begin
                    //vid_std_lower <= spi_read_data;
                    reg_read_data[reg_index] <= spi_read_data;
                    reg_index <= reg_index + 1;
                    //state <= ST_READ_VIDEO_FORMAT_B;
                    //spi_read_addr <= REG_VIDEO_FORMAT_352_B_1;
                    //spi_read_req <= 1'b1;
                    state <= ST_IDLE;
                end
            end
            
            //ST_READ_VIDEO_FORMAT_B: begin
            //    if (spi_busy) begin
            //        state <= ST_READ_VIDEO_FORMAT_B_WAIT;
            //        spi_read_req <= 1'b0;
            //    end
            //end
            //
            //ST_READ_VIDEO_FORMAT_B_WAIT: begin
            //    if (~spi_busy) begin
            //        vid_std_upper <= spi_read_data;
            //        state <= ST_IDLE;
            //    end
            //end
            
            default: begin //idle
                //reg_index <= reg_index + 1;
                
                if (~spi_busy & stat_poll) begin
                    state <= ST_READ_REG;
                    spi_read_addr <= REG_ADDR[reg_index];
                    spi_read_req <= 1'b1;
                end
            end
        endcase
    end
end

always @(posedge clk) begin: spi_state_machine_blk
    if (~rst_b) begin
        spi_state <= ST_SPI_IDLE;
        spi_clk_enable <= 1'b0;
        spi_busy <= 1'b0;
        spi_reading <= 1'b0;
        spi_cs <= 1'b1;
    end
    else begin
        
        case(spi_state)
            ST_SPI_WRITE_CMD: begin
                if (spi_clk_falling) begin
                    spi_cs <= 1'b0;
                    spi_clk_enable <= 1'b1;
                    spi_bit_cnt <= spi_bit_cnt - 1;
                    spi_mosi <= spi_read_cmd[spi_bit_cnt];
                    
                    if (~(|spi_bit_cnt)) begin
                        if (spi_reading) begin
                            spi_state <= ST_SPI_READ_WAIT;
                            spi_bit_cnt <= READ_WAIT_TIME;
                        end
                        else begin
                            spi_state <= ST_SPI_CMD_GAP;
                            spi_bit_cnt <= CMD_GAP_TIME;
                        end
                    end
                end
            end
            
            ST_SPI_READ_WAIT: begin //waste time between cmd write and read
                if (spi_clk_falling) begin
                    spi_clk_enable <= 1'b0;
                    spi_mosi <= 1'b0;
                    spi_bit_cnt <= spi_bit_cnt - 1;
                    if (~(|spi_bit_cnt)) begin
                        spi_state <= ST_SPI_READ_STAT;
                        spi_clk_enable <= 1'b1;
                        spi_bit_cnt <= 15;
                    end
                end
            end
            
            ST_SPI_READ_STAT: begin
                if (spi_clk_rising) begin
                    spi_read_data[spi_bit_cnt] <= spi_miso;
                    spi_bit_cnt <= spi_bit_cnt - 1;
                    
                    if (~(|spi_bit_cnt)) begin
                        spi_state <= ST_SPI_CMD_GAP;
                        spi_bit_cnt <= CMD_GAP_TIME;
                    end
                end
            end
            
            ST_SPI_CMD_GAP: begin
                if (spi_clk_falling) begin
                    spi_clk_enable <= 1'b0;
                    spi_bit_cnt <= spi_bit_cnt - 1;
                    
                    if (~(|spi_bit_cnt)) begin
                        spi_state <= ST_SPI_IDLE;
                        spi_busy <= 1'b0;
                        spi_cs <= 1'b1;
                    end
                end
            end
            
            default: begin //idle
                spi_reading <= 1'b0;
                
                if (spi_clk_falling) begin
                    if (spi_read_req) begin
                        spi_state <= ST_SPI_WRITE_CMD;
                        spi_busy <= 1'b1;
                        spi_reading <= 1'b1;
                        spi_read_cmd <= {1'b1, 3'b0, spi_read_addr};
                    end
                    
                    spi_clk_enable <= 1'b0;
                end
            end
        endcase
    end
end

endmodule
