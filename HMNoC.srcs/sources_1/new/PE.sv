`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/27/2019 07:20:21 AM
// Design Name: 
// Module Name: PE
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module PE #( parameter DATA_WIDTH = 16,
			 parameter ADDR_WIDTH = 9,
			 parameter W_READ_ADDR = 0,
			 parameter A_READ_ADDR = 100,
			 parameter PSUM_ADDR = 500)
		   ( input clk, reset,
			 input [DATA_WIDTH-1:0] act_in,
			 input [DATA_WIDTH-1:0] filt_in,
			 input load_en, start,
			 output logic [DATA_WIDTH-1:0] pe_out,
			 output logic [DATA_WIDTH-1:0] act_out
    );
	
	parameter int kernel_size = 3;
	parameter int act_size = 5;
	
	enum logic [2:0] {IDLE=3'b000, READ_W=3'b001, READ_A=3'b010, COMPUTE=3'b011,
					  WRITE=3'b100, LOAD_W=3'b101, LOAD_A=3'b110} state;
	
// ScratchPad Instantiation
	logic read_en, write_en;
	logic [ADDR_WIDTH-1:0] w_addr, r_addr;
	logic [DATA_WIDTH-1:0] r_data, w_data;
	
	SPad spad_pe0 ( .clk(clk), .reset(reset), 
					.read_req(read_en),
					.write_en(write_en), 
					.r_addr(r_addr), 
					.w_addr(w_addr),
					.w_data(w_data),
					.r_data(r_data)
					);
					

	logic [DATA_WIDTH-1:0] psum_reg;
	logic [DATA_WIDTH-1:0] sum_in;
	logic sum_in_mux_sel;
	logic [DATA_WIDTH-1:0] psum_reg_out;
	logic [DATA_WIDTH-1:0] act_reg_out;
	
	logic [DATA_WIDTH-1:0] act_in_reg;
	logic [DATA_WIDTH-1:0] filt_in_reg;
	
	logic mac_en;
	//MAC Instantiation
	
	MAC  #( .IN_BITWIDTH(DATA_WIDTH),
			     .OUT_BITWIDTH(DATA_WIDTH) )
	mac_0
				( .a_in(act_in_reg),
				  .w_in(filt_in_reg),
				  .sum_in(sum_in),
				  .en(mac_en),
				  .clk(clk),
				  .out(psum_reg)
				);
			
	mux2 #( .WIDTH(DATA_WIDTH) ) mux2_0 ( .a_in(psum_reg), 
										.b_in(16'b0), 
										.sel(sum_in_mux_sel), 
										.out(sum_in) 
										);
	
	
	logic [1:0] read_count;
	logic [3:0] filt_count;
	
	// FSM for PE
	always@(posedge clk) begin
		$display("State: %s", state.name());
		if(reset) begin
			//Initialize registers
			filt_count <= 0;
			sum_in_mux_sel = 0;
			act_reg_out <= 0;
			read_count <= 0;
			
			//Initialize scratchpad inputs
			w_addr <= W_READ_ADDR;
			r_addr <= W_READ_ADDR;
			w_data <= 0;
			write_en <= 0;
			read_en <= 0;
			
			mac_en <= 0;
			
			state <= IDLE;
		end
		else begin
			case(state)
				IDLE:begin
					if(start) begin
						r_addr <= W_READ_ADDR;
						filt_count <= 0;
						read_en <= 1;
						state <= READ_W;
					end else begin
						if(load_en) begin
							w_addr <= W_READ_ADDR;
							w_data <= filt_in;
							write_en <= 1;
							filt_count <= 0;
							state <= LOAD_W;
						end else begin
							write_en <= 0;
							state <= IDLE;
						end
					end
				end
				
				READ_W:begin
					//read_en <= 1;
					r_addr <= A_READ_ADDR + filt_count;
					filt_in_reg <= r_data;
					filt_count <= filt_count + 1;
					
					$display("Weight read: %d from address: %d", r_data, r_addr);
					$display("Read Enable: %d", read_en);
					
					state <= READ_A;
				end
				
				READ_A:begin
					$display("Act read: %d from address: %d", r_data, r_addr);
					$display("Read Enable: %d", read_en);
					act_in_reg <= r_data;
					r_addr <= W_READ_ADDR + filt_count;
					mac_en <= 1;
					state <= COMPUTE;
				end
					
				COMPUTE:begin
				$display("Weight in reg: %d  |  Act in reg: %d", filt_in_reg, act_in_reg);
				$display("MAC out: %d", psum_reg);
				
					mac_en <= 0;
					if(filt_count == kernel_size) begin
						act_in_reg <= r_data;
						read_en <= 0;
						w_addr <= PSUM_ADDR;
						write_en <= 1;
						state <= WRITE;
					end else begin
						if(filt_count == 0) begin
							sum_in_mux_sel = 0;
						end else begin
							sum_in_mux_sel = 1;	
						end
						state <= READ_W;
					end
				end
				
				WRITE:begin
					w_data <= psum_reg;
					state <= IDLE;
				end
				
				LOAD_W:begin
				$display("Weight write: %d to address: %d", filt_in, w_addr);
				$display("Write Enable: %d", write_en);
					if(load_en) begin						
						if(filt_count == (kernel_size-1)) begin
							w_addr <= A_READ_ADDR;
							w_data <= act_in;
							filt_count <= 0;
							state <= LOAD_A;
						end else begin
							w_data <= filt_in;
							w_addr <= w_addr + 1;
							filt_count <= filt_count + 1;
							state <= LOAD_W;
						end
					end else begin
						state <= IDLE;
					end
				end
				
				LOAD_A:begin
				$display("Act write: %d to address: %d", act_in,  w_addr);
				$display("Write Enable: %d", write_en);
					if(load_en) begin						
						if(filt_count == (act_size-1)) begin
							write_en <= 0;
							state <= IDLE;
						end else begin
							w_data <= act_in;
							w_addr <= w_addr + 1;
							filt_count <= filt_count + 1;
							state <= LOAD_A;
						end
					end else begin
						read_en <= 1;
						state <= IDLE;
					end
				end
			endcase
		end
	end
						
	assign pe_out = psum_reg;
	assign act_out = act_reg_out;

endmodule