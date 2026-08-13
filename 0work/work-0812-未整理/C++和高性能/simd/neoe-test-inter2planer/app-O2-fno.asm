
./app-O2-fno:     file format elf64-littleaarch64


Disassembly of section .init:

00000000004005c8 <_init>:
  4005c8:	d503201f 	nop
  4005cc:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  4005d0:	910003fd 	mov	x29, sp
  4005d4:	9400004b 	bl	400700 <call_weak_fn>
  4005d8:	a8c17bfd 	ldp	x29, x30, [sp], #16
  4005dc:	d65f03c0 	ret

Disassembly of section .plt:

00000000004005e0 <.plt>:
  4005e0:	a9bf7bf0 	stp	x16, x30, [sp, #-16]!
  4005e4:	b0000090 	adrp	x16, 411000 <__FRAME_END__+0xf910>
  4005e8:	f947fe11 	ldr	x17, [x16, #4088]
  4005ec:	913fe210 	add	x16, x16, #0xff8
  4005f0:	d61f0220 	br	x17
  4005f4:	d503201f 	nop
  4005f8:	d503201f 	nop
  4005fc:	d503201f 	nop

0000000000400600 <memcpy@plt>:
  400600:	d0000090 	adrp	x16, 412000 <memcpy@GLIBC_2.17>
  400604:	f9400211 	ldr	x17, [x16]
  400608:	91000210 	add	x16, x16, #0x0
  40060c:	d61f0220 	br	x17

0000000000400610 <free@plt>:
  400610:	d0000090 	adrp	x16, 412000 <memcpy@GLIBC_2.17>
  400614:	f9400611 	ldr	x17, [x16, #8]
  400618:	91002210 	add	x16, x16, #0x8
  40061c:	d61f0220 	br	x17

0000000000400620 <memset@plt>:
  400620:	d0000090 	adrp	x16, 412000 <memcpy@GLIBC_2.17>
  400624:	f9400a11 	ldr	x17, [x16, #16]
  400628:	91004210 	add	x16, x16, #0x10
  40062c:	d61f0220 	br	x17

0000000000400630 <__libc_start_main@plt>:
  400630:	d0000090 	adrp	x16, 412000 <memcpy@GLIBC_2.17>
  400634:	f9400e11 	ldr	x17, [x16, #24]
  400638:	91006210 	add	x16, x16, #0x18
  40063c:	d61f0220 	br	x17

0000000000400640 <malloc@plt>:
  400640:	d0000090 	adrp	x16, 412000 <memcpy@GLIBC_2.17>
  400644:	f9401211 	ldr	x17, [x16, #32]
  400648:	91008210 	add	x16, x16, #0x20
  40064c:	d61f0220 	br	x17

0000000000400650 <abort@plt>:
  400650:	d0000090 	adrp	x16, 412000 <memcpy@GLIBC_2.17>
  400654:	f9401611 	ldr	x17, [x16, #40]
  400658:	9100a210 	add	x16, x16, #0x28
  40065c:	d61f0220 	br	x17

0000000000400660 <__gmon_start__@plt>:
  400660:	d0000090 	adrp	x16, 412000 <memcpy@GLIBC_2.17>
  400664:	f9401a11 	ldr	x17, [x16, #48]
  400668:	9100c210 	add	x16, x16, #0x30
  40066c:	d61f0220 	br	x17

0000000000400670 <printf@plt>:
  400670:	d0000090 	adrp	x16, 412000 <memcpy@GLIBC_2.17>
  400674:	f9401e11 	ldr	x17, [x16, #56]
  400678:	9100e210 	add	x16, x16, #0x38
  40067c:	d61f0220 	br	x17

Disassembly of section .text:

0000000000400680 <main>:
  400680:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  400684:	910003fd 	mov	x29, sp
  400688:	94000166 	bl	400c20 <banchMark>
  40068c:	940001f1 	bl	400e50 <banchMark2>
  400690:	52800000 	mov	w0, #0x0                   	// #0
  400694:	a8c17bfd 	ldp	x29, x30, [sp], #16
  400698:	d65f03c0 	ret
  40069c:	d503201f 	nop
  4006a0:	d503201f 	nop
  4006a4:	d503201f 	nop
  4006a8:	d503201f 	nop
  4006ac:	d503201f 	nop
  4006b0:	d503201f 	nop
  4006b4:	d503201f 	nop
  4006b8:	d503201f 	nop
  4006bc:	d503201f 	nop

00000000004006c0 <_start>:
  4006c0:	d503201f 	nop
  4006c4:	d280001d 	mov	x29, #0x0                   	// #0
  4006c8:	d280001e 	mov	x30, #0x0                   	// #0
  4006cc:	aa0003e5 	mov	x5, x0
  4006d0:	f94003e1 	ldr	x1, [sp]
  4006d4:	910023e2 	add	x2, sp, #0x8
  4006d8:	910003e6 	mov	x6, sp
  4006dc:	90000000 	adrp	x0, 400000 <__abi_tag-0x254>
  4006e0:	911bd000 	add	x0, x0, #0x6f4
  4006e4:	d2800003 	mov	x3, #0x0                   	// #0
  4006e8:	d2800004 	mov	x4, #0x0                   	// #0
  4006ec:	97ffffd1 	bl	400630 <__libc_start_main@plt>
  4006f0:	97ffffd8 	bl	400650 <abort@plt>

00000000004006f4 <__wrap_main>:
  4006f4:	d503201f 	nop
  4006f8:	17ffffe2 	b	400680 <main>

00000000004006fc <_dl_relocate_static_pie>:
  4006fc:	d65f03c0 	ret

0000000000400700 <call_weak_fn>:
  400700:	b0000080 	adrp	x0, 411000 <__FRAME_END__+0xf910>
  400704:	f947f000 	ldr	x0, [x0, #4064]
  400708:	b4000040 	cbz	x0, 400710 <call_weak_fn+0x10>
  40070c:	17ffffd5 	b	400660 <__gmon_start__@plt>
  400710:	d65f03c0 	ret

0000000000400714 <deregister_tm_clones>:
  400714:	d0000080 	adrp	x0, 412000 <memcpy@GLIBC_2.17>
  400718:	91014001 	add	x1, x0, #0x50
  40071c:	d0000080 	adrp	x0, 412000 <memcpy@GLIBC_2.17>
  400720:	91014000 	add	x0, x0, #0x50
  400724:	eb00003f 	cmp	x1, x0
  400728:	54000160 	b.eq	400754 <deregister_tm_clones+0x40>  // b.none
  40072c:	d10043ff 	sub	sp, sp, #0x10
  400730:	b0000001 	adrp	x1, 401000 <banchMark2+0x1b0>
  400734:	f940ac21 	ldr	x1, [x1, #344]
  400738:	f90007e1 	str	x1, [sp, #8]
  40073c:	b4000081 	cbz	x1, 40074c <deregister_tm_clones+0x38>
  400740:	aa0103f0 	mov	x16, x1
  400744:	910043ff 	add	sp, sp, #0x10
  400748:	d61f0200 	br	x16
  40074c:	910043ff 	add	sp, sp, #0x10
  400750:	d65f03c0 	ret
  400754:	d65f03c0 	ret

0000000000400758 <register_tm_clones>:
  400758:	d0000080 	adrp	x0, 412000 <memcpy@GLIBC_2.17>
  40075c:	91014001 	add	x1, x0, #0x50
  400760:	d0000080 	adrp	x0, 412000 <memcpy@GLIBC_2.17>
  400764:	91014000 	add	x0, x0, #0x50
  400768:	cb000021 	sub	x1, x1, x0
  40076c:	d2800042 	mov	x2, #0x2                   	// #2
  400770:	9343fc21 	asr	x1, x1, #3
  400774:	9ac20c21 	sdiv	x1, x1, x2
  400778:	b4000161 	cbz	x1, 4007a4 <register_tm_clones+0x4c>
  40077c:	d10043ff 	sub	sp, sp, #0x10
  400780:	b0000002 	adrp	x2, 401000 <banchMark2+0x1b0>
  400784:	f940b042 	ldr	x2, [x2, #352]
  400788:	f90007e2 	str	x2, [sp, #8]
  40078c:	b4000082 	cbz	x2, 40079c <register_tm_clones+0x44>
  400790:	aa0203f0 	mov	x16, x2
  400794:	910043ff 	add	sp, sp, #0x10
  400798:	d61f0200 	br	x16
  40079c:	910043ff 	add	sp, sp, #0x10
  4007a0:	d65f03c0 	ret
  4007a4:	d65f03c0 	ret

00000000004007a8 <__do_global_dtors_aux>:
  4007a8:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
  4007ac:	910003fd 	mov	x29, sp
  4007b0:	f9000bf3 	str	x19, [sp, #16]
  4007b4:	d0000093 	adrp	x19, 412000 <memcpy@GLIBC_2.17>
  4007b8:	39414260 	ldrb	w0, [x19, #80]
  4007bc:	35000080 	cbnz	w0, 4007cc <__do_global_dtors_aux+0x24>
  4007c0:	97ffffd5 	bl	400714 <deregister_tm_clones>
  4007c4:	52800020 	mov	w0, #0x1                   	// #1
  4007c8:	39014260 	strb	w0, [x19, #80]
  4007cc:	f9400bf3 	ldr	x19, [sp, #16]
  4007d0:	a8c27bfd 	ldp	x29, x30, [sp], #32
  4007d4:	d65f03c0 	ret

00000000004007d8 <frame_dummy>:
  4007d8:	17ffffe0 	b	400758 <register_tm_clones>
  4007dc:	d503201f 	nop

00000000004007e0 <priv_ao_copy_inter2plan0>:
  4007e0:	a9ba7bfd 	stp	x29, x30, [sp, #-96]!
  4007e4:	f100001f 	cmp	x0, #0x0
  4007e8:	fa401864 	ccmp	x3, #0x0, #0x4, ne  // ne = any
  4007ec:	910003fd 	mov	x29, sp
  4007f0:	a9025bf5 	stp	x21, x22, [sp, #32]
  4007f4:	aa0003f6 	mov	x22, x0
  4007f8:	a90363f7 	stp	x23, x24, [sp, #48]
  4007fc:	aa0303f7 	mov	x23, x3
  400800:	54000580 	b.eq	4008b0 <priv_ao_copy_inter2plan0+0xd0>  // b.none
  400804:	53037c58 	lsr	w24, w2, #3
  400808:	a9046bf9 	stp	x25, x26, [sp, #64]
  40080c:	2a0103f9 	mov	w25, w1
  400810:	1ad80822 	udiv	w2, w1, w24
  400814:	1b027f00 	mul	w0, w24, w2
  400818:	6b01001f 	cmp	w0, w1
  40081c:	54000403 	b.cc	40089c <priv_ao_copy_inter2plan0+0xbc>  // b.lo, b.ul, b.last
  400820:	eb1702df 	cmp	x22, x23
  400824:	54000540 	b.eq	4008cc <priv_ao_copy_inter2plan0+0xec>  // b.none
  400828:	a90153f3 	stp	x19, x20, [sp, #16]
  40082c:	2a1903fa 	mov	w26, w25
  400830:	52800013 	mov	w19, #0x0                   	// #0
  400834:	f9002bfb 	str	x27, [sp, #80]
  400838:	2a1803fb 	mov	w27, w24
  40083c:	34000219 	cbz	w25, 40087c <priv_ao_copy_inter2plan0+0x9c>
  400840:	2a1303f4 	mov	w20, w19
  400844:	531f7a75 	lsl	w21, w19, #1
  400848:	8b1502c1 	add	x1, x22, x21
  40084c:	aa1b03e2 	mov	x2, x27
  400850:	8b1402e0 	add	x0, x23, x20
  400854:	97ffff6b 	bl	400600 <memcpy@plt>
  400858:	8b1b02a1 	add	x1, x21, x27
  40085c:	8b1a0280 	add	x0, x20, x26
  400860:	0b180273 	add	w19, w19, w24
  400864:	8b0102c1 	add	x1, x22, x1
  400868:	8b0002e0 	add	x0, x23, x0
  40086c:	aa1b03e2 	mov	x2, x27
  400870:	97ffff64 	bl	400600 <memcpy@plt>
  400874:	6b13033f 	cmp	w25, w19
  400878:	54fffe48 	b.hi	400840 <priv_ao_copy_inter2plan0+0x60>  // b.pmore
  40087c:	a94153f3 	ldp	x19, x20, [sp, #16]
  400880:	52800000 	mov	w0, #0x0                   	// #0
  400884:	a9446bf9 	ldp	x25, x26, [sp, #64]
  400888:	f9402bfb 	ldr	x27, [sp, #80]
  40088c:	a9425bf5 	ldp	x21, x22, [sp, #32]
  400890:	a94363f7 	ldp	x23, x24, [sp, #48]
  400894:	a8c67bfd 	ldp	x29, x30, [sp], #96
  400898:	d65f03c0 	ret
  40089c:	2a1803e3 	mov	w3, w24
  4008a0:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  4008a4:	91066000 	add	x0, x0, #0x198
  4008a8:	97ffff72 	bl	400670 <printf@plt>
  4008ac:	17ffffdd 	b	400820 <priv_ao_copy_inter2plan0+0x40>
  4008b0:	aa0003e1 	mov	x1, x0
  4008b4:	aa0303e2 	mov	x2, x3
  4008b8:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  4008bc:	9105a000 	add	x0, x0, #0x168
  4008c0:	97ffff6c 	bl	400670 <printf@plt>
  4008c4:	12800000 	mov	w0, #0xffffffff            	// #-1
  4008c8:	17fffff1 	b	40088c <priv_ao_copy_inter2plan0+0xac>
  4008cc:	aa1603e2 	mov	x2, x22
  4008d0:	aa1603e1 	mov	x1, x22
  4008d4:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  4008d8:	9107a000 	add	x0, x0, #0x1e8
  4008dc:	97ffff65 	bl	400670 <printf@plt>
  4008e0:	12800000 	mov	w0, #0xffffffff            	// #-1
  4008e4:	a9446bf9 	ldp	x25, x26, [sp, #64]
  4008e8:	17ffffe9 	b	40088c <priv_ao_copy_inter2plan0+0xac>
  4008ec:	d503201f 	nop

00000000004008f0 <priv_ao_copy_inter2plan1>:
  4008f0:	a9bc7bfd 	stp	x29, x30, [sp, #-64]!
  4008f4:	f100001f 	cmp	x0, #0x0
  4008f8:	fa401864 	ccmp	x3, #0x0, #0x4, ne  // ne = any
  4008fc:	910003fd 	mov	x29, sp
  400900:	a90153f3 	stp	x19, x20, [sp, #16]
  400904:	aa0003f3 	mov	x19, x0
  400908:	aa0303f4 	mov	x20, x3
  40090c:	540004a0 	b.eq	4009a0 <priv_ao_copy_inter2plan1+0xb0>  // b.none
  400910:	a9025bf5 	stp	x21, x22, [sp, #32]
  400914:	53037c56 	lsr	w22, w2, #3
  400918:	f9001bf7 	str	x23, [sp, #48]
  40091c:	2a0103f7 	mov	w23, w1
  400920:	1ad60835 	udiv	w21, w1, w22
  400924:	1b157ec0 	mul	w0, w22, w21
  400928:	6b01001f 	cmp	w0, w1
  40092c:	540002e3 	b.cc	400988 <priv_ao_copy_inter2plan1+0x98>  // b.lo, b.ul, b.last
  400930:	eb14027f 	cmp	x19, x20
  400934:	54000440 	b.eq	4009bc <priv_ao_copy_inter2plan1+0xcc>  // b.none
  400938:	6b1702df 	cmp	w22, w23
  40093c:	52800004 	mov	w4, #0x0                   	// #0
  400940:	d2800001 	mov	x1, #0x0                   	// #0
  400944:	54000168 	b.hi	400970 <priv_ao_copy_inter2plan1+0x80>  // b.pmore
  400948:	78e45a62 	ldrsh	w2, [x19, w4, uxtw #1]
  40094c:	11000485 	add	w5, w4, #0x1
  400950:	0b0102a0 	add	w0, w21, w1
  400954:	78217a82 	strh	w2, [x20, x1, lsl #1]
  400958:	91000421 	add	x1, x1, #0x1
  40095c:	11000884 	add	w4, w4, #0x2
  400960:	78e57a62 	ldrsh	w2, [x19, x5, lsl #1]
  400964:	6b0102bf 	cmp	w21, w1
  400968:	78207a82 	strh	w2, [x20, x0, lsl #1]
  40096c:	54fffee8 	b.hi	400948 <priv_ao_copy_inter2plan1+0x58>  // b.pmore
  400970:	a9425bf5 	ldp	x21, x22, [sp, #32]
  400974:	52800000 	mov	w0, #0x0                   	// #0
  400978:	f9401bf7 	ldr	x23, [sp, #48]
  40097c:	a94153f3 	ldp	x19, x20, [sp, #16]
  400980:	a8c47bfd 	ldp	x29, x30, [sp], #64
  400984:	d65f03c0 	ret
  400988:	2a1603e3 	mov	w3, w22
  40098c:	2a1503e2 	mov	w2, w21
  400990:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400994:	91066000 	add	x0, x0, #0x198
  400998:	97ffff36 	bl	400670 <printf@plt>
  40099c:	17ffffe5 	b	400930 <priv_ao_copy_inter2plan1+0x40>
  4009a0:	aa0003e1 	mov	x1, x0
  4009a4:	aa0303e2 	mov	x2, x3
  4009a8:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  4009ac:	9105a000 	add	x0, x0, #0x168
  4009b0:	97ffff30 	bl	400670 <printf@plt>
  4009b4:	12800000 	mov	w0, #0xffffffff            	// #-1
  4009b8:	17fffff1 	b	40097c <priv_ao_copy_inter2plan1+0x8c>
  4009bc:	aa1303e2 	mov	x2, x19
  4009c0:	aa1303e1 	mov	x1, x19
  4009c4:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  4009c8:	9107a000 	add	x0, x0, #0x1e8
  4009cc:	97ffff29 	bl	400670 <printf@plt>
  4009d0:	12800000 	mov	w0, #0xffffffff            	// #-1
  4009d4:	a9425bf5 	ldp	x21, x22, [sp, #32]
  4009d8:	f9401bf7 	ldr	x23, [sp, #48]
  4009dc:	17ffffe8 	b	40097c <priv_ao_copy_inter2plan1+0x8c>

00000000004009e0 <priv_ao_copy_inter2plan2>:
  4009e0:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  4009e4:	f100001f 	cmp	x0, #0x0
  4009e8:	fa401864 	ccmp	x3, #0x0, #0x4, ne  // ne = any
  4009ec:	910003fd 	mov	x29, sp
  4009f0:	54000760 	b.eq	400adc <priv_ao_copy_inter2plan2+0xfc>  // b.none
  4009f4:	7100405f 	cmp	w2, #0x10
  4009f8:	54000681 	b.ne	400ac8 <priv_ao_copy_inter2plan2+0xe8>  // b.any
  4009fc:	eb03001f 	cmp	x0, x3
  400a00:	53017c22 	lsr	w2, w1, #1
  400a04:	540007a0 	b.eq	400af8 <priv_ao_copy_inter2plan2+0x118>  // b.none
  400a08:	8b214068 	add	x8, x3, w1, uxtw
  400a0c:	12000447 	and	w7, w2, #0x3
  400a10:	53037c21 	lsr	w1, w1, #3
  400a14:	340003e1 	cbz	w1, 400a90 <priv_ao_copy_inter2plan2+0xb0>
  400a18:	d37c7026 	ubfiz	x6, x1, #4, #29
  400a1c:	2a0103e5 	mov	w5, w1
  400a20:	8b060006 	add	x6, x0, x6
  400a24:	aa0803e2 	mov	x2, x8
  400a28:	aa0303e1 	mov	x1, x3
  400a2c:	d503201f 	nop
  400a30:	79c00004 	ldrsh	w4, [x0]
  400a34:	91002021 	add	x1, x1, #0x8
  400a38:	781f8024 	sturh	w4, [x1, #-8]
  400a3c:	91004000 	add	x0, x0, #0x10
  400a40:	91002042 	add	x2, x2, #0x8
  400a44:	78df2004 	ldursh	w4, [x0, #-14]
  400a48:	781f8044 	sturh	w4, [x2, #-8]
  400a4c:	78df4004 	ldursh	w4, [x0, #-12]
  400a50:	781fa024 	sturh	w4, [x1, #-6]
  400a54:	78df6004 	ldursh	w4, [x0, #-10]
  400a58:	781fa044 	sturh	w4, [x2, #-6]
  400a5c:	78df8004 	ldursh	w4, [x0, #-8]
  400a60:	781fc024 	sturh	w4, [x1, #-4]
  400a64:	78dfa004 	ldursh	w4, [x0, #-6]
  400a68:	781fc044 	sturh	w4, [x2, #-4]
  400a6c:	78dfc004 	ldursh	w4, [x0, #-4]
  400a70:	eb0000df 	cmp	x6, x0
  400a74:	781fe024 	sturh	w4, [x1, #-2]
  400a78:	78dfe004 	ldursh	w4, [x0, #-2]
  400a7c:	781fe044 	sturh	w4, [x2, #-2]
  400a80:	54fffd81 	b.ne	400a30 <priv_ao_copy_inter2plan2+0x50>  // b.any
  400a84:	d37df0a1 	lsl	x1, x5, #3
  400a88:	8b010063 	add	x3, x3, x1
  400a8c:	8b010108 	add	x8, x8, x1
  400a90:	34000167 	cbz	w7, 400abc <priv_ao_copy_inter2plan2+0xdc>
  400a94:	d37f04e2 	ubfiz	x2, x7, #1, #2
  400a98:	91000805 	add	x5, x0, #0x2
  400a9c:	d2800001 	mov	x1, #0x0                   	// #0
  400aa0:	78e17804 	ldrsh	w4, [x0, x1, lsl #1]
  400aa4:	78216864 	strh	w4, [x3, x1]
  400aa8:	78e178a4 	ldrsh	w4, [x5, x1, lsl #1]
  400aac:	78216904 	strh	w4, [x8, x1]
  400ab0:	91000821 	add	x1, x1, #0x2
  400ab4:	eb02003f 	cmp	x1, x2
  400ab8:	54ffff41 	b.ne	400aa0 <priv_ao_copy_inter2plan2+0xc0>  // b.any
  400abc:	52800000 	mov	w0, #0x0                   	// #0
  400ac0:	a8c17bfd 	ldp	x29, x30, [sp], #16
  400ac4:	d65f03c0 	ret
  400ac8:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400acc:	9108a000 	add	x0, x0, #0x228
  400ad0:	97fffee8 	bl	400670 <printf@plt>
  400ad4:	12800000 	mov	w0, #0xffffffff            	// #-1
  400ad8:	17fffffa 	b	400ac0 <priv_ao_copy_inter2plan2+0xe0>
  400adc:	aa0003e1 	mov	x1, x0
  400ae0:	aa0303e2 	mov	x2, x3
  400ae4:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400ae8:	9105a000 	add	x0, x0, #0x168
  400aec:	97fffee1 	bl	400670 <printf@plt>
  400af0:	12800000 	mov	w0, #0xffffffff            	// #-1
  400af4:	17fffff3 	b	400ac0 <priv_ao_copy_inter2plan2+0xe0>
  400af8:	aa0003e2 	mov	x2, x0
  400afc:	b0000001 	adrp	x1, 401000 <banchMark2+0x1b0>
  400b00:	9107a020 	add	x0, x1, #0x1e8
  400b04:	aa0203e1 	mov	x1, x2
  400b08:	97fffeda 	bl	400670 <printf@plt>
  400b0c:	12800000 	mov	w0, #0xffffffff            	// #-1
  400b10:	17ffffec 	b	400ac0 <priv_ao_copy_inter2plan2+0xe0>
  400b14:	d503201f 	nop
  400b18:	d503201f 	nop
  400b1c:	d503201f 	nop

0000000000400b20 <priv_ao_copy_inter2plan3>:
  400b20:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  400b24:	f100001f 	cmp	x0, #0x0
  400b28:	fa401864 	ccmp	x3, #0x0, #0x4, ne  // ne = any
  400b2c:	910003fd 	mov	x29, sp
  400b30:	540005c0 	b.eq	400be8 <priv_ao_copy_inter2plan3+0xc8>  // b.none
  400b34:	7100405f 	cmp	w2, #0x10
  400b38:	540004e1 	b.ne	400bd4 <priv_ao_copy_inter2plan3+0xb4>  // b.any
  400b3c:	eb03001f 	cmp	x0, x3
  400b40:	53017c26 	lsr	w6, w1, #1
  400b44:	54000600 	b.eq	400c04 <priv_ao_copy_inter2plan3+0xe4>  // b.none
  400b48:	8b214067 	add	x7, x3, w1, uxtw
  400b4c:	120004c6 	and	w6, w6, #0x3
  400b50:	53037c21 	lsr	w1, w1, #3
  400b54:	340003c1 	cbz	w1, 400bcc <priv_ao_copy_inter2plan3+0xac>
  400b58:	d37c7024 	ubfiz	x4, x1, #4, #29
  400b5c:	2a0103e5 	mov	w5, w1
  400b60:	8b040004 	add	x4, x0, x4
  400b64:	aa0703e2 	mov	x2, x7
  400b68:	aa0303e1 	mov	x1, x3
  400b6c:	d503201f 	nop
__attribute__ ((__always_inline__, __gnu_inline__, __artificial__))
vld2_s16 (const int16_t * __a)
{
  int16x4x2_t ret;
  __builtin_aarch64_simd_oi __o;
  __o = __builtin_aarch64_ld2v4hi ((const __builtin_aarch64_simd_hi *) __a);
  400b70:	0c408400 	ld2	{v0.4h, v1.4h}, [x0]
  400b74:	91004000 	add	x0, x0, #0x10
  400b78:	eb04001f 	cmp	x0, x4

__extension__ extern __inline void
__attribute__ ((__always_inline__, __gnu_inline__, __artificial__))
vst1_s16 (int16_t *__a, int16x4_t __b)
{
  __builtin_aarch64_st1v4hi ((__builtin_aarch64_simd_hi *) __a, __b);
  400b7c:	fc008420 	str	d0, [x1], #8
  400b80:	fc008441 	str	d1, [x2], #8
  400b84:	54ffff61 	b.ne	400b70 <priv_ao_copy_inter2plan3+0x50>  // b.any
  400b88:	d37df0a1 	lsl	x1, x5, #3
  400b8c:	8b010063 	add	x3, x3, x1
  400b90:	8b0100e7 	add	x7, x7, x1
  400b94:	34000166 	cbz	w6, 400bc0 <priv_ao_copy_inter2plan3+0xa0>
  400b98:	d37f04c1 	ubfiz	x1, x6, #1, #2
  400b9c:	91000885 	add	x5, x4, #0x2
  400ba0:	d2800000 	mov	x0, #0x0                   	// #0
  400ba4:	78e07882 	ldrsh	w2, [x4, x0, lsl #1]
  400ba8:	78206862 	strh	w2, [x3, x0]
  400bac:	78e078a2 	ldrsh	w2, [x5, x0, lsl #1]
  400bb0:	782068e2 	strh	w2, [x7, x0]
  400bb4:	91000800 	add	x0, x0, #0x2
  400bb8:	eb01001f 	cmp	x0, x1
  400bbc:	54ffff41 	b.ne	400ba4 <priv_ao_copy_inter2plan3+0x84>  // b.any
  400bc0:	52800000 	mov	w0, #0x0                   	// #0
  400bc4:	a8c17bfd 	ldp	x29, x30, [sp], #16
  400bc8:	d65f03c0 	ret
  400bcc:	aa0003e4 	mov	x4, x0
  400bd0:	17fffff1 	b	400b94 <priv_ao_copy_inter2plan3+0x74>
  400bd4:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400bd8:	91096000 	add	x0, x0, #0x258
  400bdc:	97fffea5 	bl	400670 <printf@plt>
  400be0:	12800000 	mov	w0, #0xffffffff            	// #-1
  400be4:	17fffff8 	b	400bc4 <priv_ao_copy_inter2plan3+0xa4>
  400be8:	aa0003e1 	mov	x1, x0
  400bec:	aa0303e2 	mov	x2, x3
  400bf0:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400bf4:	9105a000 	add	x0, x0, #0x168
  400bf8:	97fffe9e 	bl	400670 <printf@plt>
  400bfc:	12800000 	mov	w0, #0xffffffff            	// #-1
  400c00:	17fffff1 	b	400bc4 <priv_ao_copy_inter2plan3+0xa4>
  400c04:	aa0003e2 	mov	x2, x0
  400c08:	b0000001 	adrp	x1, 401000 <banchMark2+0x1b0>
  400c0c:	9107a020 	add	x0, x1, #0x1e8
  400c10:	aa0203e1 	mov	x1, x2
  400c14:	97fffe97 	bl	400670 <printf@plt>
  400c18:	12800000 	mov	w0, #0xffffffff            	// #-1
  400c1c:	17ffffea 	b	400bc4 <priv_ao_copy_inter2plan3+0xa4>

0000000000400c20 <banchMark>:
  400c20:	a9bc7bfd 	stp	x29, x30, [sp, #-64]!
  400c24:	d280a000 	mov	x0, #0x500                 	// #1280
  400c28:	910003fd 	mov	x29, sp
  400c2c:	a90153f3 	stp	x19, x20, [sp, #16]
  400c30:	a9025bf5 	stp	x21, x22, [sp, #32]
  400c34:	97fffe83 	bl	400640 <malloc@plt>
  400c38:	aa0003f3 	mov	x19, x0
  400c3c:	d280a000 	mov	x0, #0x500                 	// #1280
  400c40:	97fffe80 	bl	400640 <malloc@plt>
  400c44:	d280a002 	mov	x2, #0x500                 	// #1280
  400c48:	aa0003f4 	mov	x20, x0
  400c4c:	52801561 	mov	w1, #0xab                  	// #171
  400c50:	97fffe74 	bl	400620 <memset@plt>
  400c54:	aa1303e0 	mov	x0, x19
  400c58:	d280a002 	mov	x2, #0x500                 	// #1280
  400c5c:	52800001 	mov	w1, #0x0                   	// #0
  400c60:	97fffe70 	bl	400620 <memset@plt>
  400c64:	aa1303e3 	mov	x3, x19
  400c68:	aa1403e0 	mov	x0, x20
  400c6c:	52800202 	mov	w2, #0x10                  	// #16
  400c70:	52805001 	mov	w1, #0x280                 	// #640
  400c74:	b9003fff 	str	wzr, [sp, #60]
  400c78:	97fffeda 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400c7c:	d53be056 	mrs	x22, cntvct_el0
  400c80:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400c84:	d503201f 	nop
  400c88:	52805001 	mov	w1, #0x280                 	// #640
  400c8c:	aa1303e3 	mov	x3, x19
  400c90:	aa1403e0 	mov	x0, x20
  400c94:	52800202 	mov	w2, #0x10                  	// #16
  400c98:	97fffed2 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400c9c:	b9403fe1 	ldr	w1, [sp, #60]
  400ca0:	710006b5 	subs	w21, w21, #0x1
  400ca4:	39400260 	ldrb	w0, [x19]
  400ca8:	0b010000 	add	w0, w0, w1
  400cac:	b9003fe0 	str	w0, [sp, #60]
  400cb0:	54fffec1 	b.ne	400c88 <banchMark+0x68>  // b.any
  400cb4:	d53be041 	mrs	x1, cntvct_el0
  400cb8:	cb160021 	sub	x1, x1, x22
  400cbc:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400cc0:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400cc4:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400cc8:	910a2000 	add	x0, x0, #0x288
  400ccc:	d343fc21 	lsr	x1, x1, #3
  400cd0:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400cd4:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400cd8:	9bc27c21 	umulh	x1, x1, x2
  400cdc:	d344fc21 	lsr	x1, x1, #4
  400ce0:	97fffe64 	bl	400670 <printf@plt>
  400ce4:	d53be056 	mrs	x22, cntvct_el0
  400ce8:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400cec:	d503201f 	nop
  400cf0:	52805001 	mov	w1, #0x280                 	// #640
  400cf4:	aa1303e3 	mov	x3, x19
  400cf8:	aa1403e0 	mov	x0, x20
  400cfc:	52800202 	mov	w2, #0x10                  	// #16
  400d00:	97fffefc 	bl	4008f0 <priv_ao_copy_inter2plan1>
  400d04:	b9403fe1 	ldr	w1, [sp, #60]
  400d08:	710006b5 	subs	w21, w21, #0x1
  400d0c:	39400260 	ldrb	w0, [x19]
  400d10:	0b010000 	add	w0, w0, w1
  400d14:	b9003fe0 	str	w0, [sp, #60]
  400d18:	54fffec1 	b.ne	400cf0 <banchMark+0xd0>  // b.any
  400d1c:	d53be041 	mrs	x1, cntvct_el0
  400d20:	cb160021 	sub	x1, x1, x22
  400d24:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400d28:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400d2c:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400d30:	910ac000 	add	x0, x0, #0x2b0
  400d34:	d343fc21 	lsr	x1, x1, #3
  400d38:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400d3c:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400d40:	9bc27c21 	umulh	x1, x1, x2
  400d44:	d344fc21 	lsr	x1, x1, #4
  400d48:	97fffe4a 	bl	400670 <printf@plt>
  400d4c:	d53be056 	mrs	x22, cntvct_el0
  400d50:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400d54:	d503201f 	nop
  400d58:	52805001 	mov	w1, #0x280                 	// #640
  400d5c:	aa1303e3 	mov	x3, x19
  400d60:	aa1403e0 	mov	x0, x20
  400d64:	52800202 	mov	w2, #0x10                  	// #16
  400d68:	97ffff1e 	bl	4009e0 <priv_ao_copy_inter2plan2>
  400d6c:	b9403fe1 	ldr	w1, [sp, #60]
  400d70:	710006b5 	subs	w21, w21, #0x1
  400d74:	39400260 	ldrb	w0, [x19]
  400d78:	0b010000 	add	w0, w0, w1
  400d7c:	b9003fe0 	str	w0, [sp, #60]
  400d80:	54fffec1 	b.ne	400d58 <banchMark+0x138>  // b.any
  400d84:	d53be041 	mrs	x1, cntvct_el0
  400d88:	cb160021 	sub	x1, x1, x22
  400d8c:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400d90:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400d94:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400d98:	910b6000 	add	x0, x0, #0x2d8
  400d9c:	d343fc21 	lsr	x1, x1, #3
  400da0:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400da4:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400da8:	9bc27c21 	umulh	x1, x1, x2
  400dac:	d344fc21 	lsr	x1, x1, #4
  400db0:	97fffe30 	bl	400670 <printf@plt>
  400db4:	d53be056 	mrs	x22, cntvct_el0
  400db8:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400dbc:	d503201f 	nop
  400dc0:	52805001 	mov	w1, #0x280                 	// #640
  400dc4:	aa1303e3 	mov	x3, x19
  400dc8:	aa1403e0 	mov	x0, x20
  400dcc:	52800202 	mov	w2, #0x10                  	// #16
  400dd0:	97ffff54 	bl	400b20 <priv_ao_copy_inter2plan3>
  400dd4:	b9403fe1 	ldr	w1, [sp, #60]
  400dd8:	710006b5 	subs	w21, w21, #0x1
  400ddc:	39400260 	ldrb	w0, [x19]
  400de0:	0b010000 	add	w0, w0, w1
  400de4:	b9003fe0 	str	w0, [sp, #60]
  400de8:	54fffec1 	b.ne	400dc0 <banchMark+0x1a0>  // b.any
  400dec:	d53be041 	mrs	x1, cntvct_el0
  400df0:	cb160021 	sub	x1, x1, x22
  400df4:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400df8:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400dfc:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400e00:	910c0000 	add	x0, x0, #0x300
  400e04:	d343fc21 	lsr	x1, x1, #3
  400e08:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400e0c:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400e10:	9bc27c21 	umulh	x1, x1, x2
  400e14:	d344fc21 	lsr	x1, x1, #4
  400e18:	97fffe16 	bl	400670 <printf@plt>
  400e1c:	b9403fe1 	ldr	w1, [sp, #60]
  400e20:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400e24:	910ca000 	add	x0, x0, #0x328
  400e28:	97fffe12 	bl	400670 <printf@plt>
  400e2c:	aa1303e0 	mov	x0, x19
  400e30:	97fffdf8 	bl	400610 <free@plt>
  400e34:	aa1403e0 	mov	x0, x20
  400e38:	a94153f3 	ldp	x19, x20, [sp, #16]
  400e3c:	a9425bf5 	ldp	x21, x22, [sp, #32]
  400e40:	a8c47bfd 	ldp	x29, x30, [sp], #64
  400e44:	17fffdf3 	b	400610 <free@plt>
  400e48:	d503201f 	nop
  400e4c:	d503201f 	nop

0000000000400e50 <banchMark2>:
  400e50:	a9bb7bfd 	stp	x29, x30, [sp, #-80]!
  400e54:	d280a000 	mov	x0, #0x500                 	// #1280
  400e58:	910003fd 	mov	x29, sp
  400e5c:	a90153f3 	stp	x19, x20, [sp, #16]
  400e60:	a9025bf5 	stp	x21, x22, [sp, #32]
  400e64:	f9001bf7 	str	x23, [sp, #48]
  400e68:	fd001fe8 	str	d8, [sp, #56]
  400e6c:	97fffdf5 	bl	400640 <malloc@plt>
  400e70:	aa0003f3 	mov	x19, x0
  400e74:	d280a000 	mov	x0, #0x500                 	// #1280
  400e78:	97fffdf2 	bl	400640 <malloc@plt>
  400e7c:	aa0003f4 	mov	x20, x0
  400e80:	d280a002 	mov	x2, #0x500                 	// #1280
  400e84:	52801561 	mov	w1, #0xab                  	// #171
  400e88:	97fffde6 	bl	400620 <memset@plt>
  400e8c:	aa1303e0 	mov	x0, x19
  400e90:	d280a002 	mov	x2, #0x500                 	// #1280
  400e94:	52800001 	mov	w1, #0x0                   	// #0
  400e98:	97fffde2 	bl	400620 <memset@plt>
  400e9c:	b9004fff 	str	wzr, [sp, #76]
  400ea0:	d53be016 	mrs	x22, cntfrq_el0
  400ea4:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400ea8:	aa1603e1 	mov	x1, x22
  400eac:	910d2000 	add	x0, x0, #0x348
  400eb0:	97fffdf0 	bl	400670 <printf@plt>
  400eb4:	aa1303e3 	mov	x3, x19
  400eb8:	aa1403e0 	mov	x0, x20
  400ebc:	52800202 	mov	w2, #0x10                  	// #16
  400ec0:	52805001 	mov	w1, #0x280                 	// #640
  400ec4:	97fffe47 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400ec8:	d53be057 	mrs	x23, cntvct_el0
  400ecc:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400ed0:	52805001 	mov	w1, #0x280                 	// #640
  400ed4:	aa1303e3 	mov	x3, x19
  400ed8:	aa1403e0 	mov	x0, x20
  400edc:	52800202 	mov	w2, #0x10                  	// #16
  400ee0:	97fffe40 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400ee4:	b9404fe1 	ldr	w1, [sp, #76]
  400ee8:	710006b5 	subs	w21, w21, #0x1
  400eec:	39400260 	ldrb	w0, [x19]
  400ef0:	0b010000 	add	w0, w0, w1
  400ef4:	b9004fe0 	str	w0, [sp, #76]
  400ef8:	54fffec1 	b.ne	400ed0 <banchMark2+0x80>  // b.any
  400efc:	d53be040 	mrs	x0, cntvct_el0
  400f00:	cb170000 	sub	x0, x0, x23
  400f04:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  400f08:	f2e825c1 	movk	x1, #0x412e, lsl #48
  400f0c:	9e670022 	fmov	d2, x1
  400f10:	9e630000 	ucvtf	d0, x0
  400f14:	9e6302c8 	ucvtf	d8, x22
  400f18:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  400f1c:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400f20:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400f24:	f2e811e1 	movk	x1, #0x408f, lsl #48
  400f28:	9e670021 	fmov	d1, x1
  400f2c:	d343fc01 	lsr	x1, x0, #3
  400f30:	1e620800 	fmul	d0, d0, d2
  400f34:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400f38:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400f3c:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400f40:	910dc000 	add	x0, x0, #0x370
  400f44:	9bc27c21 	umulh	x1, x1, x2
  400f48:	1e681800 	fdiv	d0, d0, d8
  400f4c:	d344fc21 	lsr	x1, x1, #4
  400f50:	1e611800 	fdiv	d0, d0, d1
  400f54:	97fffdc7 	bl	400670 <printf@plt>
  400f58:	d53be056 	mrs	x22, cntvct_el0
  400f5c:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400f60:	52805001 	mov	w1, #0x280                 	// #640
  400f64:	aa1303e3 	mov	x3, x19
  400f68:	aa1403e0 	mov	x0, x20
  400f6c:	52800202 	mov	w2, #0x10                  	// #16
  400f70:	97fffe60 	bl	4008f0 <priv_ao_copy_inter2plan1>
  400f74:	b9404fe1 	ldr	w1, [sp, #76]
  400f78:	710006b5 	subs	w21, w21, #0x1
  400f7c:	39400260 	ldrb	w0, [x19]
  400f80:	0b010000 	add	w0, w0, w1
  400f84:	b9004fe0 	str	w0, [sp, #76]
  400f88:	54fffec1 	b.ne	400f60 <banchMark2+0x110>  // b.any
  400f8c:	d53be040 	mrs	x0, cntvct_el0
  400f90:	cb160000 	sub	x0, x0, x22
  400f94:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  400f98:	f2e825c1 	movk	x1, #0x412e, lsl #48
  400f9c:	9e670022 	fmov	d2, x1
  400fa0:	9e630000 	ucvtf	d0, x0
  400fa4:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  400fa8:	f2e811e1 	movk	x1, #0x408f, lsl #48
  400fac:	9e670021 	fmov	d1, x1
  400fb0:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400fb4:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400fb8:	d343fc01 	lsr	x1, x0, #3
  400fbc:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400fc0:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400fc4:	1e620800 	fmul	d0, d0, d2
  400fc8:	b0000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  400fcc:	910ea000 	add	x0, x0, #0x3a8
  400fd0:	9bc27c21 	umulh	x1, x1, x2
  400fd4:	1e681800 	fdiv	d0, d0, d8
  400fd8:	d344fc21 	lsr	x1, x1, #4
  400fdc:	1e611800 	fdiv	d0, d0, d1
  400fe0:	97fffda4 	bl	400670 <printf@plt>
  400fe4:	d53be056 	mrs	x22, cntvct_el0
  400fe8:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400fec:	d503201f 	nop
  400ff0:	52805001 	mov	w1, #0x280                 	// #640
  400ff4:	aa1303e3 	mov	x3, x19
  400ff8:	aa1403e0 	mov	x0, x20
  400ffc:	52800202 	mov	w2, #0x10                  	// #16
  401000:	97fffe78 	bl	4009e0 <priv_ao_copy_inter2plan2>
  401004:	b9404fe1 	ldr	w1, [sp, #76]
  401008:	710006b5 	subs	w21, w21, #0x1
  40100c:	39400260 	ldrb	w0, [x19]
  401010:	0b010000 	add	w0, w0, w1
  401014:	b9004fe0 	str	w0, [sp, #76]
  401018:	54fffec1 	b.ne	400ff0 <banchMark2+0x1a0>  // b.any
  40101c:	d53be040 	mrs	x0, cntvct_el0
  401020:	cb160000 	sub	x0, x0, x22
  401024:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  401028:	f2e825c1 	movk	x1, #0x412e, lsl #48
  40102c:	9e670022 	fmov	d2, x1
  401030:	9e630000 	ucvtf	d0, x0
  401034:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  401038:	f2e811e1 	movk	x1, #0x408f, lsl #48
  40103c:	9e670021 	fmov	d1, x1
  401040:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  401044:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  401048:	d343fc01 	lsr	x1, x0, #3
  40104c:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  401050:	f2e41882 	movk	x2, #0x20c4, lsl #48
  401054:	1e620800 	fmul	d0, d0, d2
  401058:	90000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  40105c:	910f8000 	add	x0, x0, #0x3e0
  401060:	9bc27c21 	umulh	x1, x1, x2
  401064:	1e681800 	fdiv	d0, d0, d8
  401068:	d344fc21 	lsr	x1, x1, #4
  40106c:	1e611800 	fdiv	d0, d0, d1
  401070:	97fffd80 	bl	400670 <printf@plt>
  401074:	d53be056 	mrs	x22, cntvct_el0
  401078:	52807d15 	mov	w21, #0x3e8                 	// #1000
  40107c:	d503201f 	nop
  401080:	52805001 	mov	w1, #0x280                 	// #640
  401084:	aa1303e3 	mov	x3, x19
  401088:	aa1403e0 	mov	x0, x20
  40108c:	52800202 	mov	w2, #0x10                  	// #16
  401090:	97fffea4 	bl	400b20 <priv_ao_copy_inter2plan3>
  401094:	b9404fe1 	ldr	w1, [sp, #76]
  401098:	710006b5 	subs	w21, w21, #0x1
  40109c:	39400260 	ldrb	w0, [x19]
  4010a0:	0b010000 	add	w0, w0, w1
  4010a4:	b9004fe0 	str	w0, [sp, #76]
  4010a8:	54fffec1 	b.ne	401080 <banchMark2+0x230>  // b.any
  4010ac:	d53be040 	mrs	x0, cntvct_el0
  4010b0:	cb160000 	sub	x0, x0, x22
  4010b4:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  4010b8:	f2e825c1 	movk	x1, #0x412e, lsl #48
  4010bc:	9e670022 	fmov	d2, x1
  4010c0:	9e630000 	ucvtf	d0, x0
  4010c4:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  4010c8:	f2e811e1 	movk	x1, #0x408f, lsl #48
  4010cc:	9e670021 	fmov	d1, x1
  4010d0:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  4010d4:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  4010d8:	d343fc01 	lsr	x1, x0, #3
  4010dc:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  4010e0:	f2e41882 	movk	x2, #0x20c4, lsl #48
  4010e4:	1e620800 	fmul	d0, d0, d2
  4010e8:	90000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  4010ec:	91106000 	add	x0, x0, #0x418
  4010f0:	9bc27c21 	umulh	x1, x1, x2
  4010f4:	1e681800 	fdiv	d0, d0, d8
  4010f8:	d344fc21 	lsr	x1, x1, #4
  4010fc:	1e611800 	fdiv	d0, d0, d1
  401100:	97fffd5c 	bl	400670 <printf@plt>
  401104:	b9404fe1 	ldr	w1, [sp, #76]
  401108:	90000000 	adrp	x0, 401000 <banchMark2+0x1b0>
  40110c:	910ca000 	add	x0, x0, #0x328
  401110:	97fffd58 	bl	400670 <printf@plt>
  401114:	aa1303e0 	mov	x0, x19
  401118:	97fffd3e 	bl	400610 <free@plt>
  40111c:	aa1403e0 	mov	x0, x20
  401120:	fd401fe8 	ldr	d8, [sp, #56]
  401124:	a94153f3 	ldp	x19, x20, [sp, #16]
  401128:	a9425bf5 	ldp	x21, x22, [sp, #32]
  40112c:	f9401bf7 	ldr	x23, [sp, #48]
  401130:	a8c57bfd 	ldp	x29, x30, [sp], #80
  401134:	17fffd37 	b	400610 <free@plt>

Disassembly of section .fini:

0000000000401138 <_fini>:
  401138:	d503201f 	nop
  40113c:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  401140:	910003fd 	mov	x29, sp
  401144:	a8c17bfd 	ldp	x29, x30, [sp], #16
  401148:	d65f03c0 	ret
