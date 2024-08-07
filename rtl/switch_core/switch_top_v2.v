`timescale 1ns / 1ps
module switch_top_v2 (
    input clk,
    input rstn,

    // input       sof,
    // input       dv,
    // input [7:0] din,

    input [127:0] i_cell_data_fifo_dout,
    input         i_cell_data_fifo_wr,
    input [ 15:0] i_cell_ptr_fifo_dout,
    input         i_cell_ptr_fifo_wr,
    output        i_cell_bp,

    input         interface_clk0,
    input         interface_clk1,
    input         interface_clk2,
    input         interface_clk3,
    input         ptr_fifo_rd0,
    input         ptr_fifo_rd1,
    input         ptr_fifo_rd2,
    input         ptr_fifo_rd3,
    input         data_fifo_rd0,
    input         data_fifo_rd1,
    input         data_fifo_rd2,
    input         data_fifo_rd3,
    output [ 7:0] data_fifo_dout0,
    output [ 7:0] data_fifo_dout1,
    output [ 7:0] data_fifo_dout2,
    output [ 7:0] data_fifo_dout3,
    output [15:0] ptr_fifo_dout0,
    output [15:0] ptr_fifo_dout1,
    output [15:0] ptr_fifo_dout2,
    output [15:0] ptr_fifo_dout3,
    output        ptr_fifo_empty0,
    output        ptr_fifo_empty1,
    output        ptr_fifo_empty2,
    output        ptr_fifo_empty3,

    output        swc_mgnt_valid,
    input         swc_mgnt_resp,
    output [ 3:0] swc_mgnt_data
);

    // wire [127:0] i_cell_data_fifo_dout;
    // wire         i_cell_data_fifo_wr;
    // wire [ 15:0] i_cell_ptr_fifo_dout;
    // wire         i_cell_ptr_fifo_wr;
    // wire         i_cell_bp;


    wire [  3:0] o_cell_fifo_wr;
    // wire [  3:0] o_cell_fifo_sel;
    wire         o_cell_first;
    wire         o_cell_last;
    wire [127:0] o_cell_fifo_din;
    wire [  7:0] o_cell_ptr;
    wire [  3:0] o_cell_bp;


    // switch_pre pre (
    //     .clk (clk),
    //     .rstn(rstn),

    //     .sof(sof),
    //     .dv (dv),
    //     .din(din),

    //     .i_cell_data_fifo_dout(i_cell_data_fifo_dout),
    //     .i_cell_data_fifo_wr(i_cell_data_fifo_wr),
    //     .i_cell_ptr_fifo_dout(i_cell_ptr_fifo_dout),
    //     .i_cell_ptr_fifo_wr(i_cell_ptr_fifo_wr),
    //     .i_cell_bp(i_cell_bp)
    // );

    switch_core_v2 core (
        .clk (clk),
        .rstn(rstn),

        .i_cell_data_fifo_din(i_cell_data_fifo_dout),
        .i_cell_data_fifo_wr(i_cell_data_fifo_wr),
        .i_cell_ptr_fifo_din(i_cell_ptr_fifo_dout),
        .i_cell_ptr_fifo_wr(i_cell_ptr_fifo_wr),
        .i_cell_bp(i_cell_bp),

        .o_cell_fifo_wr(o_cell_fifo_wr),
        // .o_cell_fifo_sel(o_cell_fifo_sel),
        .o_cell_fifo_din(o_cell_fifo_din),
        .o_cell_first(o_cell_first),
        .o_cell_last(o_cell_last),
        .o_cell_bp(o_cell_bp),

        .swc_mgnt_valid( swc_mgnt_valid              ),
        .swc_mgnt_data ( swc_mgnt_data        [ 3:0] ),
        .swc_mgnt_resp ( swc_mgnt_resp               )
    );

    switch_post_top u_switch_post_top (
        .clk (clk),
        .rstn(rstn),

        .o_cell_fifo_wr(o_cell_fifo_wr),
        // .o_cell_fifo_sel(o_cell_fifo_sel),
        .o_cell_fifo_din(o_cell_fifo_din),
        .o_cell_first(o_cell_first),
        .o_cell_last(o_cell_last),
        .o_cell_bp(o_cell_bp),

        .interface_clk0(interface_clk0),
        .interface_clk1(interface_clk1),
        .interface_clk2(interface_clk2),
        .interface_clk3(interface_clk3),
        .ptr_fifo_rd0(ptr_fifo_rd0),
        .ptr_fifo_rd1(ptr_fifo_rd1),
        .ptr_fifo_rd2(ptr_fifo_rd2),
        .ptr_fifo_rd3(ptr_fifo_rd3),
        .data_fifo_rd0(data_fifo_rd0),
        .data_fifo_rd1(data_fifo_rd1),
        .data_fifo_rd2(data_fifo_rd2),
        .data_fifo_rd3(data_fifo_rd3),
        .data_fifo_dout0(data_fifo_dout0),
        .data_fifo_dout1(data_fifo_dout1),
        .data_fifo_dout2(data_fifo_dout2),
        .data_fifo_dout3(data_fifo_dout3),
        .ptr_fifo_dout0(ptr_fifo_dout0),
        .ptr_fifo_dout1(ptr_fifo_dout1),
        .ptr_fifo_dout2(ptr_fifo_dout2),
        .ptr_fifo_dout3(ptr_fifo_dout3),
        .ptr_fifo_empty0(ptr_fifo_empty0),
        .ptr_fifo_empty1(ptr_fifo_empty1),
        .ptr_fifo_empty2(ptr_fifo_empty2),
        .ptr_fifo_empty3(ptr_fifo_empty3)
    );

endmodule
