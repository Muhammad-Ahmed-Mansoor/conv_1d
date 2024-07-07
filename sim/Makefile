clean:
	@ls | grep -v Makefile | xargs rm -rf

compile:
	vlog ../rtl/* ../tb/* -sv12compat

run:
	vsim -voptargs="+acc" work.tb_conv_1d