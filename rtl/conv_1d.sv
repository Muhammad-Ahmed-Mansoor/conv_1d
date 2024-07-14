module conv_1d #(
    parameter DATA_WIDTH        = 8,
    parameter MAX_KERNEL_LENGTH = 8,

    // Do not override
    localparam PRODUCT_WIDTH = (DATA_WIDTH * 2),
    localparam RESULT_WIDTH  = PRODUCT_WIDTH + $clog2(MAX_KERNEL_LENGTH)
) (
    input logic clk,
    input logic arst_n,

    // Signal streaming interface
    input  logic                  kernel_load, // 0: Signal | 1: Kernel
    input  logic [DATA_WIDTH-1:0] signal_data,
    input  logic                  signal_vld,
    input  logic                  signal_last,
    output logic                  signal_rdy,

    // Output data interface
    output logic [RESULT_WIDTH-1:0] result_data,
    output logic                    result_vld,
    output logic                    result_last,
    input  logic                    result_rdy
);

  ///////////////////////////////////////////////
  // CONTROL FSM AND RELATED LOGIC
  ///////////////////////////////////////////////

  // Control signal declarations
  logic conv_done; // Even after signal_last, it takes some cycles for the convolution to truly be done
  logic conv_stall; // The convolution datapath may need to be stalled

  // State encoding
  typedef enum logic [1:0] {
    RESET  = 2'b00,
    KERNEL = 2'b01,
    CONV = 2'b10,
    CONV_FINAL = 2'b11  
  } states_t;

  // State variables
  states_t current_state, next_state; 

  // State transition
  always_ff @(posedge clk or negedge arst_n) begin
    if(!arst_n) begin
      current_state <= RESET;
    end
    else begin
      current_state <= next_state;
    end
  end

  // Next state logic
  always_comb begin
    unique case (current_state)
      RESET: begin
        if(kernel_load && signal_vld && !signal_last)
          next_state = KERNEL;
        else if (!kernel_load && signal_vld && !signal_last)
          next_state = CONV;
        else
          next_state = RESET;
      end

      KERNEL: begin
        if(signal_last && signal_vld)
          next_state = RESET;
        else
          next_state = KERNEL;
      end

      CONV: begin
        if(signal_last && signal_vld)
          next_state = CONV_FINAL;
        else
          next_state = CONV;
      end

      CONV_FINAL: begin
        if(conv_done)
          next_state = RESET;
        else
          next_state = CONV_FINAL;
      end
    endcase
  end

  // Logic for stalling the convolution pipeline
  assign conv_stall = !result_rdy && result_vld;

  //////////////////////////////////////
  // State dependent internal signals
  /////////////////////////////////////
  logic kernel_new; // Signal to start shifting in the a kernel
  logic kernel_shift; // Signal to continue shifting in the kernel
  logic signal_shift_en; // Signal to enable shifting in the signal
  always_comb begin
   unique case current_state
    RESET: begin
      signal_rdy = ~conv_stall | kernel_load; // If we are expecting a kernel load operation, then a conv_stall should not lead to backpressure
      signal_shift_en = ~kernel_load & signal_vld & ~conv_stall;
      kernel_new = kernel_load & signal_vld;
      kernel_shift = 1'b0;
    end
    KERNEL: begin
      signal_shift_en = 1'b0;
      signal_rdy = 1'b1;
      kernel_new = 1'b0;
      kernel_shift = signal_vld;
    end
    CONV: begin
      signal_rdy = ~conv_stall;
      signal_shift_en = signal_vld & ~conv_stall;
      kernel_new = 1'b0;
      kernel_shift = 1'b0;
    end
    CONV_FINAL: begin
      signal_rdy = 1'b0; // No new input is acceptable in this mode
      signal_shift_en = 1'b1;
      kernel_new = 1'b0;
      kernel_shift = 1'b0;
    end
   endcase
  end
  
  //////////////////////////////////
  // Kernel Load Logic
  //////////////////////////////////
  logic [MAX_KERNEL_LENGTH-1:0][DATA_WIDTH-1:0] kernel;
  logic [$clog2(MAX_KERNEL_LENGTH):0] kernel_length;

  always_ff @(posedge clk, negedge arst_n) begin
    if(!arst_n) begin
      kernel <= '0;
      kernel_length <= MAX_KERNEL_LENGTH; // By default, we assume the kernel has MAX_KERNEL_LENGTH zeros
    end
    else if (kernel_new) begin
      kernel <= {signal_data, {(MAX_KERNEL_LENGTH-1){DATA_WIDTH'0}}};
      kernel_length <= kernel_length + 1'b1;
    end
    else if (kernel_shift) begin
      kernel <= {signal_data, kernel[MAX_KERNEL_LENGTH-1:1]};
      kernel_length <= kernel_length + 1'b1;
    end
  end






  ///////////////////////////////////
  // Convolution Datapath
  ///////////////////////////////////

  // Signal buffer (shift register) equal in length to kernel. We also need to buffer the value 
  // of signal_vld to syncronize with the pipeline stage associated with the signal_buf shift register.
  logic [MAX_KERNEL_LENGTH-1:0][DATA_WIDTH-1:0] signal_buf;
  logic shift_vld;
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      signal_buf <= '0;
      shift_vld <= 1'b0;
    end else begin 
      if (signal_vld) begin // If vld is not asserted, we do not shift in the data
        signal_buf <= {signal_data, signal_buf[MAX_KERNEL_LENGTH-1:1]}; 
      end
      shift_vld <= signal_vld;
    end
  end


  // Calculate the products
  logic [MAX_KERNEL_LENGTH-1:0][PRODUCT_WIDTH-1:0] products;
  always_comb begin
    for (int i = 0; i < MAX_KERNEL_LENGTH; i++) begin
      products[i] = kernel[i] * signal_buf[i];
    end
  end

  // Buffer the products and its validity: if signal_vld was not asserted, the product is also not vld
  logic [MAX_KERNEL_LENGTH-1:0][PRODUCT_WIDTH-1:0] products_buf;
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
    for (int i = 0; i < MAX_KERNEL_LENGTH; i++) begin
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
