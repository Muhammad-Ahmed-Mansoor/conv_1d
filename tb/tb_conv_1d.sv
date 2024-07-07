module tb_conv_1d;

	//////////////////////////
	// Parameters
	/////////////////////////
  localparam DATA_WIDTH = 8;
  localparam KERNEL_SIZE = 4;
  localparam PRODUCT_WIDTH = (DATA_WIDTH * 2);
  localparam RESULT_WIDTH = PRODUCT_WIDTH + $clog2(KERNEL_SIZE);

	/////////////////////////
  // DUT interface signals
	//////////////////////////
  logic                                    clk;
  logic                                    arst_n;
  logic [  DATA_WIDTH-1:0]                 signal_data;
  logic                                    signal_vld;
  logic                                    signal_last;
  logic                                    signal_rdy;
  logic [ KERNEL_SIZE-1:0][DATA_WIDTH-1:0] kernel;
  logic [RESULT_WIDTH-1:0]                 result_data;
  logic                                    result_vld;
  logic                                    result_last;
  logic                                    result_rdy;

	//////////////////////////
	// DUT instantiation
	/////////////////////////
  conv_1d #(
      .DATA_WIDTH (DATA_WIDTH),
      .KERNEL_SIZE(KERNEL_SIZE)
  ) dut (.*);

	/////////////////////
	// Drive clock
	/////////////////////
	localparam CLK_PERIOD = 10;
	initial begin
		clk = 0; 
		forever begin
			clk = ~clk; #(CLK_PERIOD/2);
		end
	end

	/////////////////////////
	// Drive DUT signals
	////////////////////////

	// Drive the constant kernel
	always_comb begin
		for (int i = 0; i<KERNEL_SIZE; i++) begin
			kernel[i] = i+1;
		end
	end

	// Drive the other signals
	initial begin
		// Initial values
		signal_data = 1'b0;
		signal_vld  = 1'b0;
		
		// Exert Reset
		arst_n = 0; #(CLK_PERIOD); arst_n = 1;

		// At each negedge of clock, update the input stream
		for (int i = 1; i<=10; i++) begin
			@(negedge clk);
			signal_data = i;

			if (i==5 || i== 6 || i == 8) begin
				signal_vld = 1'b0;
			end
			else begin
				signal_vld = 1'b1;
			end
		end

		@(negedge clk);
		signal_data = 0;

		#100;
		$finish;

	end

endmodule
