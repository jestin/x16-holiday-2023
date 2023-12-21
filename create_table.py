from fxpmath import Fxp

start_scale = 3.75
end_scale = 1.0
num_rows = 120

inx = Fxp(start_scale, True, 15, 9)
# inx.round = "around"
# print(inx.bin(frac_dot=True))
# print((inx << 1).bin( frac_dot=True))
# print(inx.hex())
# print("$" + inx.hex()[2:])
# print(inx())

for i in range(num_rows):
    # print(inx.bin(frac_dot=True))
    inxlo = "$" + (inx << 1).hex()[4:]
    # print(((inx & 0b111111100000000) << 1).bin(frac_dot=True))
    inxhi = "$" + ((inx << 1) & 0b111111100000000).hex()[2:4]
    # inxhi = ((inx & 0b11111000000000) << 1).bin(frac_dot=True)

    # inxlo = "0"
    # inxhi = "2"

    print(".byte " + inxlo + "," + inxhi + "," + str(0) + "," + str(0) + ","
            + str(0) + "," + str(0) + "," + str(i) + "," + str(0))

    inx -= (start_scale - end_scale) / num_rows
