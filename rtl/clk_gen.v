`timescale 1ns/1ps
`default_nettype none
// 备用PLL封装：当前27MHz直分频方案不例化本模块。
// 硬件使用前必须提供经Gowin验证的audio_pll_adapter实现。
module clk_gen #(
    // 同步器之后连续确认的音频时钟周期数；合法值>=1。
    // 默认16是启动保护选择，并非PLL锁定时间的硬件保证。
    parameter integer LOCK_STABLE_CYCLES = 16
) (
    input  wire clk_27m,
    input  wire rst_n,
    output wire clk_audio,
    output wire pll_locked,
    output wire audio_rst_n
);
    // 适配层合同：reset高有效，locked为真实PLL锁定输出。
    // 实际IP名/端口/复位极性由适配层按生成文件映射，禁止猜参数。
    audio_pll_adapter u_pll (
        .clk_27m(clk_27m), .reset(~rst_n),
        .clk_audio(clk_audio), .locked(pll_locked)
    );

    function integer count_width;
        input integer value;
        integer remaining;
        begin
            remaining=value-1;
            count_width=0;
            while(remaining>0) begin
                count_width=count_width+1;
                remaining=remaining>>1;
            end
            if(count_width<1) count_width=1;
        end
    endfunction
    localparam integer COUNT_WIDTH=count_width(LOCK_STABLE_CYCLES);
    localparam [COUNT_WIDTH-1:0] STABLE_LAST=LOCK_STABLE_CYCLES-1;
    wire reset_permit = rst_n & pll_locked;
    reg [1:0] release_sync;
    reg [COUNT_WIDTH-1:0] stable_count;
    reg reset_released;

    // 外部复位或失锁异步拉低；在音频域经过两级触发器同步释放。
    always @(posedge clk_audio or negedge reset_permit) begin
        if(!reset_permit)
            release_sync <= 2'b00;
        else
            release_sync <= {release_sync[0],1'b1};
    end

    // 同步器之后再确认N个周期；任意失锁立即清除确认进度。
    always @(posedge clk_audio or negedge reset_permit) begin
        if(!reset_permit) begin
            stable_count <= {COUNT_WIDTH{1'b0}};
            reset_released <= 1'b0;
        end else if(!release_sync[1]) begin
            stable_count <= {COUNT_WIDTH{1'b0}};
            reset_released <= 1'b0;
        end else if(!reset_released) begin
            if(stable_count==STABLE_LAST)
                reset_released <= 1'b1;
            else
                stable_count <= stable_count+1'b1;
        end
    end
    assign audio_rst_n=reset_released;
endmodule
`default_nettype wire
