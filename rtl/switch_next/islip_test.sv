module islip_test (
    input           clk,
    input           rst,
    input           arb_valid_in,
    output          arb_ready_in,
    input   [ 3:0]  rx_req_vect [3:0],
    input   [ 3:0]  tx_rdy_vect,
    output          arb_valid_out,
    input           arb_ready_out,
    output  [ 3:0]  arb_vect [3:0]
);

    // idle state
    parameter   ARB_STATE_IDLE = 1;
    // grant state, check for tx-side round robin for input selection
    parameter   ARB_STATE_GRNT = 2;
    // accept state, check for rx-side round robin for output selection
    parameter   ARB_STATE_ACPT = 4;
    // wait state, wait for other module to acquire arbitation result
    parameter   ARB_STATE_WAIT = 8;

    reg     [ 3:0]  arb_state, arb_state_next;

    reg     [ 1:0]  rx_rndrb_state          [ 3:0];
    reg     [ 1:0]  tx_rndrb_state          [ 3:0];

    reg     [ 3:0]  rx_rndrb_vect_in_reg    [ 3:0];
    wire    [ 3:0]  rx_rndrb_vect_in        [ 3:0];
    wire    [ 3:0]  rx_rndrb_vect_out       [ 3:0]; 
    wire    [ 1:0]  rx_rndrb_bin_out        [ 3:0];

    reg     [ 3:0]  rndrb_vect_reg          [ 3:0];

    wire    [ 3:0]  tx_rndrb_vect_in        [ 3:0];
    wire    [ 3:0]  tx_rndrb_vect_out       [ 3:0];
    reg     [ 3:0]  tx_rndrb_vect_out_reg   [ 3:0];
    wire    [ 1:0]  tx_rndrb_bin_out        [ 3:0];

    genvar  n, m;

    always @(*) begin
        case(arb_state)
            ARB_STATE_IDLE:
                arb_state_next  =   (arb_valid_in) ? ARB_STATE_GRNT : ARB_STATE_IDLE;
            ARB_STATE_GRNT:
                arb_state_next  =   ARB_STATE_ACPT;
            ARB_STATE_ACPT:
                arb_state_next  =   ARB_STATE_WAIT;
            ARB_STATE_WAIT:
                arb_state_next  =   (arb_ready_out) ? ARB_STATE_IDLE : ARB_STATE_IDLE;
            default:
                arb_state_next  =   arb_state;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            arb_state   <=  ARB_STATE_IDLE;
        end
        else begin
            arb_state   <=  arb_state_next;
        end
    end

    assign      arb_ready_in    =   (arb_state == ARB_STATE_IDLE);
    assign      arb_valid_out   =   (arb_state == ARB_STATE_WAIT);

    generate

        for (n = 0; n < 4; n = n + 1) begin : input_reg
            always @(posedge clk) begin
                if (rst) begin
                    rx_rndrb_vect_in_reg[n] <=  'b0;
                end
                else begin
                    rx_rndrb_vect_in_reg[n] <=  rx_req_vect[n];
                end
            end
            for (m = 0; m < 4; m = m + 1) begin
                assign  rx_rndrb_vect_in[n][m]  =   rx_rndrb_vect_in_reg[m][n];
            end   
        end

        for (n = 0; n < 4; n = n + 1) begin : output_arbit
            rnd_rb_ppe #(
                .RR_WIDTH   (4)
            ) u_o_arb (
                .rr_vec_in  (rx_rndrb_vect_in       [n]),
                .rr_priority(rx_rndrb_state         [n]),
                .rr_vec_out (rx_rndrb_vect_out      [n]),
                .rr_bin_out (rx_rndrb_bin_out       [n])
            );
        end

        for (n = 0; n < 4; n = n + 1) begin : intermediate_reg
            always @(posedge clk) begin
                if (rst) begin
                    rndrb_vect_reg[n]   <=  'b0; 
                end
                else if (arb_state == ARB_STATE_GRNT) begin
                    rndrb_vect_reg[n]   <=  rx_rndrb_vect_out[n];
                end
            end
            for (m = 0; m < 4; m = m + 1) begin
                assign  tx_rndrb_vect_in[n][m]  =   (rndrb_vect_reg[m][n]);
            end
        end

        for (n = 0; n < 4; n = n + 1) begin : input_arbit
            rnd_rb_ppe #(
                .RR_WIDTH   (4)
            ) u_i_arb (
                .rr_vec_in  (tx_rndrb_vect_in   [n]),
                .rr_priority(tx_rndrb_state     [n]),
                .rr_vec_out (tx_rndrb_vect_out  [n]),
                .rr_bin_out (tx_rndrb_bin_out   [n])
            );
        end

        for (n = 0; n < 4; n = n + 1) begin : output_reg
            always @(posedge clk) begin
                if (rst) begin
                    tx_rndrb_vect_out_reg[n]    <=  'b0;
                end
                else if (arb_state == ARB_STATE_ACPT) begin
                    tx_rndrb_vect_out_reg[n]    <=  tx_rndrb_vect_out[n];
                end
            end
            assign  arb_vect[n] =   tx_rndrb_vect_out_reg[n];
        end

        for (n = 0; n < 4; n = n + 1) begin : rx_rndrb_state_update
            always @(posedge clk) begin
                if (rst) begin
                    rx_rndrb_state[n]   <=  'b0;
                end
                else if (arb_state == ARB_STATE_ACPT) begin
                    if (tx_rndrb_bin_out[rx_rndrb_bin_out[n]] == n && rx_rndrb_vect_out[n] != 'b0) begin
                        rx_rndrb_state[n]   <=  rx_rndrb_bin_out[n] + 1'b1;
                    end
                end
            end 
        end

        for (n = 0; n < 4; n = n + 1) begin : tx_rndrb_state_update
            always @(posedge clk) begin
                if (rst) begin
                    tx_rndrb_state[n]   <=  'b0;
                end
                else if (arb_state == ARB_STATE_ACPT) begin
                    if (arb_vect[n] != 'b0) begin
                        tx_rndrb_state[n]   <=  tx_rndrb_bin_out[n] + 1'b1;
                    end
                end
            end
        end
    endgenerate

endmodule