# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


def color(dut):
    """The (R, G, B) levels (0-3) on the Tiny VGA Pmod: uo_out = {hsync, B0, G0, R0, vsync, B1, G1, R1}."""
    v = int(dut.uo_out.value)
    return tuple(((v >> hi) & 1) * 2 + ((v >> lo) & 1) for hi, lo in ((0, 4), (1, 5), (2, 6)))


def hsync(dut):
    return int(dut.uo_out.value[7])  # (The colors are undefined until the first line's spans are computed.)


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset, with no gamepad buttons pressed.
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Test project behavior")
    assert dut.uio_oe.value == 0

    # VGA line timing: hsync (active low) is a 96-cycle pulse every 800 cycles.
    async def cycles_until(level):
        cycles = 0
        while hsync(dut) != level:
            await ClockCycles(dut.clk, 1)
            cycles += 1
            assert cycles <= 1000, "hsync stuck"
        return cycles

    await cycles_until(1)
    await cycles_until(0)  # Line 0's hsync starts (at its pixel 656).
    pulse = await cycles_until(1)
    rest = await cycles_until(0)  # Line 1's.
    assert pulse == 96, f"hsync pulse of {pulse} cycles"
    assert pulse + rest == 800, f"line of {pulse + rest} cycles"

    # Line 2's pixels, from its pixel 0, 144 cycles after line 1's hsync starts. At reset, the nearest ring's
    # opening is centered, with a radius of about 200 pixels, so the top lines show its wall (white), with the
    # (empty) depth meter (light gray) at x 16-31.
    await cycles_until(1)
    await cycles_until(0)
    await ClockCycles(dut.clk, 144)
    pixels = []
    for x in range(640):
        pixels.append(color(dut))
        await ClockCycles(dut.clk, 1)
    assert all(c == (2, 2, 2) for c in pixels[16:32]), f"depth meter: {pixels[16:32]}"
    assert all(c == (3, 3, 3) for c in pixels[32:640]), f"wall: {set(pixels[32:640])}"
