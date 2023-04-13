`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Athlon
// 
// Create Date: 2022/05/11 16:43:39
// Design Name: GMII TX interface, version 3
// Module Name: mac_t_gmii_tte_v3
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// Reworked again, ieee 1588 compatibility added
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// Only 2 step clock support available now, need refinement
//////////////////////////////////////////////////////////////////////////////////

module mac_t_gmii_tte_v4(
    input           rstn_sys,       // async reset, system side
    input           rstn_mac,       // async reset, (g)mii side
    input           sys_clk,        // sys clk
    input           tx_clk,         // mii tx clk
    input           gtx_clk,        // gmii tx clk, 125MHz, External
    output          interface_clk,  // interface clk, drive output fifo
    output          gtx_dv,         // (g)mii tx valid
    output  [ 7:0]  gtx_d,          // (g)mii tx data

    input   [ 1:0]  speed,          // speed from mdio

    // normal dataflow
    output reg      data_fifo_rd,
    input   [ 7:0]  data_fifo_din,  // registered output, better timing
    input           data_fifo_empty,
    output reg      ptr_fifo_rd, 
    input   [15:0]  ptr_fifo_din,
    input           ptr_fifo_empty,
    // tte dataflow
    output reg      tdata_fifo_rd,
    input   [ 7:0]  tdata_fifo_din,
    input           tdata_fifo_empty,
    output reg      tptr_fifo_rd,
    input   [15:0]  tptr_fifo_din,
    input           tptr_fifo_empty,
    // 1588 interface
    input   [31:0]  counter_ns,         // current time
    output  [63:0]  counter_delay       // broadcast slave-master delay to rx port, update delay_resp
);

    localparam  PTP_VALUE_HI        =   8'h88;  // high byte of ptp ethertype
    localparam  PTP_VALUE_LO        =   8'hf7;  // low byte of ptp ethertype
    localparam  PTP_TYPE_SYNC       =   4'h0;   // MsgType Sync
    localparam  PTP_TYPE_DYRQ       =   4'h1;   // MsgType Delay_Req
    localparam  PTP_TYPE_FLUP       =   4'h8;   // MsgType Follow_Up
    localparam  PTP_TYPE_DYRP       =   4'h9;   // MsgType Delay_Resp

    localparam  MAC_TX_STATE_IDLE   =   1;  // idle state, wait for new packet
    localparam  MAC_TX_STATE_STA1   =   2;  // start state 1, read ptr
    localparam  MAC_TX_STATE_STA2   =   4;  // start state 2, process ptr
    localparam  MAC_TX_STATE_STA3   =   8;  // start state 3, wait until data arrive
    localparam  MAC_TX_STATE_STA4   =   16; // start state 4, wait until buffer is filled
    localparam  MAC_TX_STATE_PREA   =   32; // preamble state, not counting
    localparam  MAC_TX_STATE_DATA   =   64; // data state, count for data bytes
    localparam  MAC_TX_STATE_CRCV   =   128;// crc state, output crc value
    localparam  MAC_TX_STATE_WAIT   =   256;// wait state, comply with standard

    localparam  PTP_TX_STATE_IDL1   =   1;  // idle state 1, wait for ptp packet
    localparam  PTP_TX_STATE_IDL2   =   2;  // idle state 2, wait for ptp packet
    localparam  PTP_TX_STATE_TYPE   =   4;  // type state, check for ptp type
    localparam  PTP_TX_STATE_SYNC   =   8;  // sync state, update master-slave latency
    localparam  PTP_TX_STATE_DYRQ   =   16; // delay_req state, update slave-master latency
    localparam  PTP_TX_STATE_FUP1   =   32; // follow_up state 1, wait for correctionField
    localparam  PTP_TX_STATE_FUP2   =   64; // follow_up state 2, update correctionField
    localparam  PTP_TX_STATE_FUP3   =   128;// follow_up state 3, replace data with new correctionField

    // no jitter clk switch
    reg     [ 1:0]  speed_reg;
    wire            speed_change;
    always @(posedge sys_clk or negedge rstn_sys) begin
        if (!rstn_sys) begin
            speed_reg   <=  2'b11;
        end
        else begin
            speed_reg   <=  speed;
        end
    end
    assign          speed_change =  |(speed ^ speed_reg);

    wire            tx_master_clk;
    reg             tx_clk_en_reg_p;
    reg             tx_clk_en_reg_n;
    reg             gtx_clk_en_reg_p;
    reg             gtx_clk_en_reg_n;

    always @(posedge tx_clk or posedge speed_change) begin
        if (speed_change) begin
            tx_clk_en_reg_p     <=  'b0;
        end
        else begin
            tx_clk_en_reg_p     <=  !speed[1] && !gtx_clk_en_reg_n;
        end
    end 
    always @(negedge tx_clk or posedge speed_change) begin
        if (speed_change) begin
            tx_clk_en_reg_n     <=  'b0;
        end
        else begin
            tx_clk_en_reg_n     <=  tx_clk_en_reg_p;
        end
    end

    always @(posedge gtx_clk or posedge speed_change) begin
        if (speed_change) begin
            gtx_clk_en_reg_p    <=  'b0;
        end
        else begin
            gtx_clk_en_reg_p    <=  speed[1] && !tx_clk_en_reg_n;
        end
    end  
    always @(negedge gtx_clk or negedge speed_change) begin
        if (speed_change) begin
            gtx_clk_en_reg_n    <=  'b0;
        end
        else begin
            gtx_clk_en_reg_n    <=  gtx_clk_en_reg_p;
        end
    end

    assign  tx_master_clk   =   (tx_clk_en_reg_n && tx_clk) || (gtx_clk_en_reg_n && gtx_clk);
    assign  interface_clk   =   tx_master_clk;

    reg     [15:0]  tx_state, tx_state_next;
    reg     [95:0]  tx_buffer;      // extended buffer for PTP operations
    reg     [ 3:0]  tx_buf_rdy;     // ready when buffer is filled
    reg     [47:0]  tx_buf_cf;      // high 48 bit of correctionField

    reg             tx_arb_dir;
    reg     [10:0]  tx_cnt_front;   // frontend count
    reg     [10:0]  tx_cnt_back;    // backend count
    reg     [10:0]  tx_cnt_back_1;
    reg     [10:0]  tx_byte_cnt;    // total byte count
    reg     [ 1:0]  tx_byte_valid;
    reg             tx_read_req;    // generate read signal for 4-bit MII

    reg     [47:0]  ptp_delay_sync; // ingress-egress delay of sync
    reg     [47:0]  ptp_delay_req;  // ingress-egress delay of delay_req
    reg     [47:0]  ptp_cf;         // updated correctionField
    wire            ptp_carry;
    wire            ptp_carry_1;
    reg             ptp_carry_reg;
    reg             ptp_carry_reg_1;
    wire    [ 7:0]  ptp_cf_add;
    wire    [ 7:0]  ptp_cf_add_1;
    reg     [31:0]  ptp_time_ts;    // timestamp from packet
    reg     [31:0]  ptp_time_now;   // timestamp of now
    reg     [31:0]  ptp_time_now_sys;   // timestamp of now, system side
    reg             ptp_time_req;       // lockup counter output for cross clk domain
    reg             ptp_time_req_mac;
    reg     [ 1:0]  ptp_time_rdy_sys;   // system side of lockup signal
    reg     [ 1:0]  ptp_time_rdy_mac;   // mac side of lockup signal

    reg             crc_init;
    reg             crc_cal;
    reg             crc_dv;
    wire    [31:0]  crc_result;
    wire    [ 7:0]  crc_dout;

    wire    [ 7:0]  tx_data_in;
    wire    [15:0]  tx_ptr_in;
    assign          tx_data_in  =   tx_arb_dir ? tdata_fifo_din : data_fifo_din;
    assign          tx_ptr_in   =   tx_arb_dir ? tptr_fifo_din  : ptr_fifo_din;

    always @(*) begin
        case(tx_state)
            'h01: tx_state_next = (!tptr_fifo_empty || !ptr_fifo_empty) ? 'h2 : 'h1;
            'h02: tx_state_next = 'h4;
            'h04: tx_state_next = 'h8;
            'h08: tx_state_next = (tx_cnt_front == tx_byte_cnt) ? 'h16 : 'h8;
            'h16: tx_state_next = (tx_cnt_back == 11'hFF8) ? 'h1 : 'h16;
        endcase
    end

    always @(posedge tx_master_clk or negedge rstn_mac) begin
        if (!rstn_mac) begin
            tx_state    <=  1;
        end
        else begin
            tx_state    <=  tx_state_next;
        end
    end

    always @(posedge tx_master_clk or negedge rstn_mac) begin
        if (!rstn_mac) begin
            tx_cnt_front    <=  'b1;
            tx_byte_valid   <=  'b0;
        end
        else begin
            if (data_fifo_rd || tdata_fifo_rd) begin
                tx_cnt_front    <=  tx_cnt_front + 1'b1;
            end
            else begin
                tx_cnt_front    <=  'b1;
            end
            tx_byte_valid   <=  {tx_byte_valid[0], (data_fifo_rd || tdata_fifo_rd)};
        end
    end

    always @(posedge tx_master_clk or negedge rstn_mac) begin
        if (!rstn_mac) begin
            tx_arb_dir      <=  'b0;
            ptr_fifo_rd     <=  'b0;
            tptr_fifo_rd    <=  'b0;
            data_fifo_rd    <=  'b0;
            tdata_fifo_rd   <=  'b0;
            tx_byte_cnt     <=  'b0;
        end        
        else begin
            if (tx_state_next == 'h1) begin
                ptr_fifo_rd     <=  'b0;
                tptr_fifo_rd    <=  'b0;
                data_fifo_rd    <=  'b0;
                tdata_fifo_rd   <=  'b0;
                tx_byte_cnt     <=  'b0;
            end
            else if (tx_state_next == 'h2) begin
                tx_arb_dir      <=  !tptr_fifo_empty;
                ptr_fifo_rd     <=  tptr_fifo_empty;
                tptr_fifo_rd    <=  !tptr_fifo_empty;
            end
            else if (tx_state_next == 'h4) begin
                ptr_fifo_rd     <=  'b0;
                tptr_fifo_rd    <=  'b0;
                data_fifo_rd    <=  !tx_arb_dir;
                tdata_fifo_rd   <=  tx_arb_dir;
            end
            else if (tx_state_next == 'h8) begin
                tx_byte_cnt     <=  tx_ptr_in[10:0];
            end
            else if (tx_state_next == 'h16) begin
                data_fifo_rd    <=  'b0;
                tdata_fifo_rd   <=  'b0;
            end
        end
    end

    reg     [15:0]  ptp_state, ptp_state_next;
    
    always @(*) begin
        case(ptp_state)
            PTP_TX_STATE_IDL1: begin
                if (tx_cnt_front == 15 && tx_data_in == PTP_VALUE_HI)
                    ptp_state_next  =   PTP_TX_STATE_IDL2;
                else
                    ptp_state_next  =   PTP_TX_STATE_IDL1;
            end
            PTP_TX_STATE_IDL2: begin
                if (tx_cnt_front == 16 && tx_data_in == PTP_VALUE_LO)
                    ptp_state_next  =   PTP_TX_STATE_TYPE;
                else
                    ptp_state_next  =   PTP_TX_STATE_IDL1;
            end
            PTP_TX_STATE_TYPE: begin
                if (tx_cnt_front == 17 && tx_data_in[3:0] == PTP_TYPE_SYNC)
                    ptp_state_next  =   PTP_TX_STATE_SYNC;
                else if (tx_cnt_front == 17 && tx_data_in[3:0] == PTP_TYPE_DYRQ)
                    ptp_state_next  =   PTP_TX_STATE_DYRQ;
                else if (tx_cnt_front == 17 && tx_data_in[3:0] == PTP_TYPE_FLUP)
                    ptp_state_next  =   PTP_TX_STATE_FUP1;
                else
                    ptp_state_next  =   PTP_TX_STATE_IDL1;
            end
            PTP_TX_STATE_SYNC: begin
                if (tx_cnt_front == 48)
                    ptp_state_next  =   PTP_TX_STATE_IDL1;
                else
                    ptp_state_next  =   PTP_TX_STATE_SYNC;
            end
            PTP_TX_STATE_DYRQ: begin
                if (tx_cnt_front == 48)
                    ptp_state_next  =   PTP_TX_STATE_IDL1;
                else
                    ptp_state_next  =   PTP_TX_STATE_DYRQ;              
            end
            PTP_TX_STATE_FUP1: begin
                if (tx_cnt_front == 30)
                    ptp_state_next  =   PTP_TX_STATE_FUP2;
                else
                    ptp_state_next  =   PTP_TX_STATE_FUP1;   
            end
            PTP_TX_STATE_FUP2: begin
                if (tx_cnt_front == 36)
                    ptp_state_next  =   PTP_TX_STATE_FUP3;
                else
                    ptp_state_next  =   PTP_TX_STATE_FUP2;
            end
            PTP_TX_STATE_FUP3: begin
                if (tx_cnt_front == 42)
                    ptp_state_next  =   PTP_TX_STATE_IDL1;
                else
                    ptp_state_next  =   PTP_TX_STATE_FUP3;       
            end
            default: begin
                ptp_state_next  =   ptp_state; 
            end
        endcase
    end

    always @(posedge tx_master_clk or negedge rstn_mac) begin
        if (!rstn_mac) begin
            ptp_state   <=  PTP_TX_STATE_IDL1;
        end
        else begin
            ptp_state   <=  ptp_state_next;
        end
    end

    always @(posedge sys_clk or negedge rstn_sys) begin
        if (!rstn_sys) begin
            ptp_time_rdy_sys    <=  'b0;
            ptp_time_now_sys    <=  'b0;
        end
        else begin
            ptp_time_rdy_sys    <=  {ptp_time_rdy_sys[0], ptp_time_req_mac};
            ptp_time_now_sys    <=  ptp_time_rdy_sys[1] ? ptp_time_now_sys : counter_ns;
        end
    end

    always @(posedge tx_master_clk or negedge rstn_mac) begin
        if (!rstn_mac) begin
            tx_buf_cf           <=  'b0;
            ptp_cf              <=  'b0;
            ptp_carry_reg       <=  'b0;
            ptp_delay_sync      <=  'b0;
            ptp_delay_req       <=  'b0;
            ptp_time_ts         <=  'b0;
            ptp_time_now        <=  'b0;
            ptp_time_req        <=  'b0;    // toggle signal
            ptp_time_req_mac    <=  'b0;    // pulse signal
            ptp_time_rdy_mac    <=  'b0;
        end
        else begin
            ptp_time_req_mac    <=  (ptp_time_req || (ptp_time_req_mac && ~ptp_time_rdy_mac[1]));
            ptp_time_rdy_mac    <=  {ptp_time_rdy_mac[0], ptp_time_rdy_sys[1]};
            ptp_time_now        <=  ptp_time_rdy_mac[1] ? ptp_time_now_sys : ptp_time_now;
            if (ptp_state == PTP_TX_STATE_SYNC) begin
                if (tx_cnt_front == 32) begin
                    ptp_time_req    <=  'b1;
                end
                else if (tx_cnt_front == 33) begin
                    ptp_time_req    <=  'b0;
                    ptp_time_ts     <=  {ptp_time_ts[23:0], tx_data_in};
                end
                else if (tx_cnt_front == 34) begin
                    ptp_time_ts     <=  {ptp_time_ts[23:0], tx_data_in};
                end
                else if (tx_cnt_front == 35) begin
                    ptp_time_ts     <=  {ptp_time_ts[23:0], tx_data_in};
                end
                else if (tx_cnt_front == 36) begin
                    ptp_time_ts     <=  {ptp_time_ts[23:0], tx_data_in};
                end
                else if (tx_cnt_front == 38) begin
                    {ptp_carry_reg_1, ptp_delay_sync[15:0]} <=  (ptp_time_now[15:0] - ptp_time_ts[15:0]);
                end
                else if (tx_cnt_front == 39) begin
                    ptp_delay_sync[31:16]   <=  (ptp_time_now[31:16] - ptp_time_ts[31:16] - ptp_carry_reg_1);
                end
                // else if (tx_cnt_front == 40) begin
                //     ptp_delay_sync[31]      <=  (ptp_time_now[31]^ptp_time_ts[31]) ? ~ptp_delay_sync[31] : ptp_delay_sync[31];
                // end
            end
            else if (ptp_state == PTP_TX_STATE_DYRQ) begin
                if (tx_cnt_front == 32) begin
                    ptp_time_req    <=  'b1;
                end
                else if (tx_cnt_front == 33) begin
                    ptp_time_req    <=  'b0;
                    ptp_time_ts     <=  {ptp_time_ts[23:0], tx_data_in};
                end
                else if (tx_cnt_front == 34) begin
                    ptp_time_ts     <=  {ptp_time_ts[23:0], tx_data_in};
                end
                else if (tx_cnt_front == 35) begin
                    ptp_time_ts     <=  {ptp_time_ts[23:0], tx_data_in};
                end
                else if (tx_cnt_front == 36) begin
                    ptp_time_ts     <=  {ptp_time_ts[23:0], tx_data_in};
                end
                else if (tx_cnt_front == 38) begin
                    {ptp_carry_reg_1, ptp_delay_req[15:0]}  <=  (ptp_time_now[15:0] - ptp_time_ts[15:0]);
                end
                else if (tx_cnt_front == 39) begin
                    ptp_delay_req[31:16]    <=  (ptp_time_now[31:16] - ptp_time_ts[31:16] - ptp_carry_reg_1);
                end
                // else if (tx_cnt_front == 40) begin
                //     ptp_delay_req[31]       <=  (ptp_time_now[31]^ptp_time_ts[31]) ? ~ptp_delay_req[31] : ptp_delay_req[31];
                // end
            end
            else if (ptp_state == PTP_TX_STATE_FUP1) begin
                if (tx_cnt_front == 30) begin
                    tx_buf_cf   <=  {tx_data_in, tx_buffer[95:56]};
                end
            end
            else if (ptp_state == PTP_TX_STATE_FUP2) begin
                if (tx_cnt_front == 31) begin
                    tx_buf_cf       <=  {tx_buf_cf[39:0], tx_buf_cf[47:40]};
                    ptp_delay_sync  <=  {ptp_delay_sync[7:0], ptp_delay_sync[31:8]};
                    ptp_cf          <=  {ptp_cf_add, ptp_cf[47:8]};
                    ptp_carry_reg   <=  ptp_carry;
                end
                if (tx_cnt_front == 32) begin
                    tx_buf_cf       <=  {tx_buf_cf[39:0], tx_buf_cf[47:40]};
                    ptp_delay_sync  <=  {ptp_delay_sync[7:0], ptp_delay_sync[31:8]};
                    ptp_cf          <=  {ptp_cf_add, ptp_cf[47:8]};
                    ptp_carry_reg   <=  ptp_carry;
                end
                if (tx_cnt_front == 33) begin
                    tx_buf_cf       <=  {tx_buf_cf[39:0], tx_buf_cf[47:40]};
                    ptp_delay_sync  <=  {ptp_delay_sync[7:0], ptp_delay_sync[31:8]};
                    ptp_cf          <=  {ptp_cf_add, ptp_cf[47:8]};
                    ptp_carry_reg   <=  ptp_carry;
                end
                if (tx_cnt_front == 34) begin
                    tx_buf_cf       <=  {tx_buf_cf[39:0], tx_buf_cf[47:40]};
                    ptp_delay_sync  <=  {ptp_delay_sync[7:0], ptp_delay_sync[31:8]};
                    ptp_cf          <=  {ptp_cf_add, ptp_cf[47:8]};
                    ptp_carry_reg   <=  ptp_carry;
                end
                if (tx_cnt_front == 35) begin
                    tx_buf_cf       <=  {tx_buf_cf[39:0], tx_buf_cf[47:40]};
                    // ptp_delay_sync  <=  {ptp_delay_sync[7:0], ptp_delay_sync[31:8]};
                    ptp_cf          <=  {ptp_cf_add_1, ptp_cf[47:8]};
                    ptp_carry_reg   <=  ptp_carry_1;
                end
                if (tx_cnt_front == 36) begin
                    tx_buf_cf       <=  {tx_buf_cf[39:0], tx_buf_cf[47:40]};
                    // ptp_delay_sync  <=  {ptp_delay_sync[7:0], ptp_delay_sync[31:8]};
                    ptp_cf          <=  {ptp_cf_add_1, ptp_cf[47:8]};
                    ptp_carry_reg   <=  ptp_carry_1;
                end
            end
            else if (ptp_state == PTP_TX_STATE_FUP3) begin
                ptp_cf  <=  ptp_cf << 8;
            end
        end
    end

    assign  {ptp_carry, ptp_cf_add}         =   tx_buf_cf[47:40] + ptp_delay_sync[7:0] + ptp_carry_reg;
    assign  {ptp_carry_1, ptp_cf_add_1}     =   tx_buf_cf[47:40] + ptp_carry_reg;

    reg     [15:0]  mii_state, mii_state_next;

    reg     [ 7:0]  mii_d;
    reg             mii_dv;

    wire    [ 7:0]  mii_d_in;
    assign          mii_d_in    =   (mii_state == 'h08)                 ?   crc_dout        :
                                    (ptp_state == PTP_TX_STATE_FUP3)    ?   ptp_cf[47:40]   :
                                    tx_buffer[7:0];

    always @(*) begin
        case(mii_state)
            'h01: mii_state_next = tx_buf_rdy[3] ? 'h2 : 'h1;
            'h02: mii_state_next = (tx_cnt_back_1 == 0) ? 'h4 : 'h2;
            'h04: mii_state_next = (tx_cnt_back_1 == tx_byte_cnt) ? 'h8 : 'h4;
            'h08: mii_state_next = !tx_buf_rdy[3] ? 'h1 : 'h8;
        endcase
    end

    always @(posedge tx_master_clk or negedge rstn_mac) begin
        if (!rstn_mac) begin
            mii_state   <=  'h1;
        end
        else begin
            mii_state   <=  mii_state_next;
        end
    end

    always @(posedge tx_master_clk or negedge rstn_mac) begin
        if (!rstn_mac) begin
            tx_buf_rdy  <=  'b0;
            crc_init    <=  'b0;
            crc_cal     <=  'b0;
            crc_dv      <=  'b0;
        end
        else begin
            if (tx_byte_valid[1]) begin
                tx_buf_rdy  <=  {tx_buf_rdy[2:0], 1'b1};
            end
            else if (mii_state == 'h08) begin
                tx_buf_rdy  <=  {tx_buf_rdy[2:0], 1'b0};
            end
            if (mii_state_next == 'h01) begin
                crc_init    <=  'b0;
                crc_cal     <=  'b0;
                crc_dv      <=  'b0;
            end
            else if (mii_state_next == 'h02) begin
                crc_init    <=  'b1;
                crc_cal     <=  'b0;
                crc_dv      <=  'b0;                
            end
            else if (mii_state_next == 'h04) begin
                crc_init    <=  'b0;
                crc_cal     <=  'b1;
                crc_dv      <=  'b1;
            end
            else if (mii_state_next == 'h08) begin
                crc_init    <=  'b0;
                crc_cal     <=  'b0;
                crc_dv      <=  'b1;                
            end
        end
    end

    always @(posedge tx_master_clk or negedge rstn_mac) begin
        if (!rstn_mac) begin
            tx_buffer       <=  {8'hd5, {7{8'h55}}, {4{8'b0}}};
            // tx_buf_cf       <=  'b0;
            tx_cnt_back     <=  11'hFF8;
            tx_cnt_back_1   <=  11'hFF9;
            mii_d           <=  'b0;
            mii_dv          <=  'b0;
        end
        else begin  // initialize tx buffer
            if (!tx_buf_rdy[3] && tx_byte_valid[1]) begin
                tx_buffer       <=  {tx_data_in, tx_buffer[95:8]};
                // tx_buf_cf       <=  {tx_data_in, tx_buf_cf[47:8]};
                mii_d           <=  'b0;
                mii_dv          <=  'b0;
            end     // send tx buffer
            else if (tx_cnt_back != tx_byte_cnt && tx_buf_rdy[3]) begin
                tx_buffer       <=  {tx_data_in, tx_buffer[95:8]};
                // tx_buf_cf       <=  {tx_data_in, tx_buf_cf[47:8]};
                // tx_cnt_back     <=  tx_cnt_back + 1'b1;
                tx_cnt_back     <=  tx_cnt_back_1;
                tx_cnt_back_1   <=  tx_cnt_back_1 + 1'b1;
                mii_d           <=  mii_d_in;
                mii_dv          <=  1'b1;
            end
            else if (mii_state_next == 'h8) begin
                mii_d           <=  mii_d_in;
                mii_dv          <=  1'b1;                
            end
            else begin
                tx_buffer       <=  {8'hd5, {7{8'h55}}, {4{8'b0}}};
                // tx_buf_cf       <=  'b0;
                tx_cnt_back     <=  11'hFF8;
                tx_cnt_back_1   <=  11'hFF9;
                mii_d           <=  'b0;
                mii_dv          <=  'b0;
            end
        end
    end

    assign      gtx_d   =   mii_d;
    assign      gtx_dv  =   mii_dv;

    crc32_8023 u_crc32_8023(
        .clk(tx_master_clk), 
        .reset(!rstn_mac), 
        .d(mii_d_in), 
        .load_init(crc_init),
        .calc(crc_cal), 
        .d_valid(crc_dv), 
        .crc_reg(crc_result), 
        .crc(crc_dout)
    );

endmodule