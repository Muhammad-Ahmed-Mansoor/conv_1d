module conv_1d #(
    parameter DATA_WIDTH  = 8,
    parameter KERNEL_SIZE = 8,

    // Do not override
    localparam PRODUCT_WIDTH = (DATA_WIDTH * 2),
    localparam RESULT_WIDTH  = PRODUCT_WIDTH + $clog2(KERNEL_SIZE)
) (
    input logic clk,
    input logic arst_n,

    // Signal streaming interface
    input  logic [DATA_WIDTH-1:0] signal_data,
    input  logic                  signal_vld,
    input  logic                  signal_last,
    output logic                  signal_rdy,

    // Fixed kernel interface
    input [KERNEL_SIZE-1:0][DATA_WIDTH-1:0] kernel,

    // Output data interface
    output logic [RESULT_WIDTH-1:0] result_data,
    output logic                    result_vld,
    output logic                    result_last,
    input  logic                    result_rdy
);

  // Signal buffer (shift register) equal in length to kernel. We also need to buffer the value 
  // of signal_vld to syncronize with the pipeline stage associated with the signal_buf shift register.
  logic [KERNEL_SIZE-1:0][DATA_WIDTH-1:0] signal_buf;
  logic shift_vld;
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      signal_buf <= '0;
      shift_vld <= 1'b0;
    end else begin 
      if (signal_vld) begin // If vld is not asserted, we do not shift in the data
        signal_buf <= {signal_data, signal_buf[KERNEL_SIZE-1:1]}; 
      end
      shift_vld <= signal_vld;
    end
  end


  // Calculate the products
  logic [KERNEL_SIZE-1:0][PRODUCT_WIDTH-1:0] products;
  always_comb begin
    for (int i = 0; i < KERNEL_SIZE; i++) begin
      products[i] = kernel[i] * signal_buf[i];
    end
  end

  // Buffer the products and its validity: if signal_vld was not asserted, the product is also not vld
  logic [KERNEL_SIZE-1:0][PRODUCT_WIDTH-1:0] products_buf;
  logic products_vld;
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      products_buf <= '0;
      products_vld <= 1'b0;
    end else begin
      products_buf <= products;
      products_vld <= shift_vld;
    end
  end

  // Calculate the sum of products
  logic [RESULT_WIDTH-1:0] sum;
  always_comb begin
    sum = 0;
    for (int i = 0; i < KERNEL_SIZE; i++) begin
      sum += products_buf[i];
    end
  end

  // Buffer the sum and also its validity: if the products weren't valid, neither is the sum
  logic [RESULT_WIDTH-1:0] sum_buf;
  logic sum_vld;
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      sum_buf <= '0;
      sum_vld <= 1'b0;
    end else begin
      sum_buf <= sum;
      sum_vld <= products_vld;
    end
  end

  // Output
  assign result_data = sum_buf;
  assign result_vld  = sum_vld;





endmodule
