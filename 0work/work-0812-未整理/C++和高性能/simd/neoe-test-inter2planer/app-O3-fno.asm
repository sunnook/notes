
./app-O3-fno:     file format elf64-littleaarch64


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
  4005e4:	b0000090 	adrp	x16, 411000 <__FRAME_END__+0xf8e0>
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
  400688:	94000172 	bl	400c50 <banchMark>
  40068c:	940001fd 	bl	400e80 <banchMark2>
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
  400700:	b0000080 	adrp	x0, 411000 <__FRAME_END__+0xf8e0>
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
  400730:	b0000001 	adrp	x1, 401000 <banchMark2+0x180>
  400734:	f940c421 	ldr	x1, [x1, #392]
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
  400780:	b0000002 	adrp	x2, 401000 <banchMark2+0x180>
  400784:	f940c842 	ldr	x2, [x2, #400]
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
  4008a0:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  4008a4:	91072000 	add	x0, x0, #0x1c8
  4008a8:	97ffff72 	bl	400670 <printf@plt>
  4008ac:	17ffffdd 	b	400820 <priv_ao_copy_inter2plan0+0x40>
  4008b0:	aa0003e1 	mov	x1, x0
  4008b4:	aa0303e2 	mov	x2, x3
  4008b8:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  4008bc:	91066000 	add	x0, x0, #0x198
  4008c0:	97ffff6c 	bl	400670 <printf@plt>
  4008c4:	12800000 	mov	w0, #0xffffffff            	// #-1
  4008c8:	17fffff1 	b	40088c <priv_ao_copy_inter2plan0+0xac>
  4008cc:	aa1603e2 	mov	x2, x22
  4008d0:	aa1603e1 	mov	x1, x22
  4008d4:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  4008d8:	91086000 	add	x0, x0, #0x218
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
  400990:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400994:	91072000 	add	x0, x0, #0x1c8
  400998:	97ffff36 	bl	400670 <printf@plt>
  40099c:	17ffffe5 	b	400930 <priv_ao_copy_inter2plan1+0x40>
  4009a0:	aa0003e1 	mov	x1, x0
  4009a4:	aa0303e2 	mov	x2, x3
  4009a8:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  4009ac:	91066000 	add	x0, x0, #0x198
  4009b0:	97ffff30 	bl	400670 <printf@plt>
  4009b4:	12800000 	mov	w0, #0xffffffff            	// #-1
  4009b8:	17fffff1 	b	40097c <priv_ao_copy_inter2plan1+0x8c>
  4009bc:	aa1303e2 	mov	x2, x19
  4009c0:	aa1303e1 	mov	x1, x19
  4009c4:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  4009c8:	91086000 	add	x0, x0, #0x218
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
  4009f0:	54000820 	b.eq	400af4 <priv_ao_copy_inter2plan2+0x114>  // b.none
  4009f4:	7100405f 	cmp	w2, #0x10
  4009f8:	54000741 	b.ne	400ae0 <priv_ao_copy_inter2plan2+0x100>  // b.any
  4009fc:	eb03001f 	cmp	x0, x3
  400a00:	53017c28 	lsr	w8, w1, #1
  400a04:	54000860 	b.eq	400b10 <priv_ao_copy_inter2plan2+0x130>  // b.none
  400a08:	8b214067 	add	x7, x3, w1, uxtw
  400a0c:	12000508 	and	w8, w8, #0x3
  400a10:	53037c21 	lsr	w1, w1, #3
  400a14:	340003e1 	cbz	w1, 400a90 <priv_ao_copy_inter2plan2+0xb0>
  400a18:	d37c7026 	ubfiz	x6, x1, #4, #29
  400a1c:	2a0103e5 	mov	w5, w1
  400a20:	8b060006 	add	x6, x0, x6
  400a24:	aa0703e2 	mov	x2, x7
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
  400a8c:	8b0100e7 	add	x7, x7, x1
  400a90:	34000228 	cbz	w8, 400ad4 <priv_ao_copy_inter2plan2+0xf4>
  400a94:	79c00001 	ldrsh	w1, [x0]
  400a98:	7100051f 	cmp	w8, #0x1
  400a9c:	79000061 	strh	w1, [x3]
  400aa0:	79c00401 	ldrsh	w1, [x0, #2]
  400aa4:	790000e1 	strh	w1, [x7]
  400aa8:	54000160 	b.eq	400ad4 <priv_ao_copy_inter2plan2+0xf4>  // b.none
  400aac:	79c00801 	ldrsh	w1, [x0, #4]
  400ab0:	7100091f 	cmp	w8, #0x2
  400ab4:	79000461 	strh	w1, [x3, #2]
  400ab8:	79c00c01 	ldrsh	w1, [x0, #6]
  400abc:	790004e1 	strh	w1, [x7, #2]
  400ac0:	540000a0 	b.eq	400ad4 <priv_ao_copy_inter2plan2+0xf4>  // b.none
  400ac4:	79c01001 	ldrsh	w1, [x0, #8]
  400ac8:	79000861 	strh	w1, [x3, #4]
  400acc:	79c01400 	ldrsh	w0, [x0, #10]
  400ad0:	790008e0 	strh	w0, [x7, #4]
  400ad4:	52800000 	mov	w0, #0x0                   	// #0
  400ad8:	a8c17bfd 	ldp	x29, x30, [sp], #16
  400adc:	d65f03c0 	ret
  400ae0:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400ae4:	91096000 	add	x0, x0, #0x258
  400ae8:	97fffee2 	bl	400670 <printf@plt>
  400aec:	12800000 	mov	w0, #0xffffffff            	// #-1
  400af0:	17fffffa 	b	400ad8 <priv_ao_copy_inter2plan2+0xf8>
  400af4:	aa0003e1 	mov	x1, x0
  400af8:	aa0303e2 	mov	x2, x3
  400afc:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400b00:	91066000 	add	x0, x0, #0x198
  400b04:	97fffedb 	bl	400670 <printf@plt>
  400b08:	12800000 	mov	w0, #0xffffffff            	// #-1
  400b0c:	17fffff3 	b	400ad8 <priv_ao_copy_inter2plan2+0xf8>
  400b10:	aa0003e2 	mov	x2, x0
  400b14:	b0000001 	adrp	x1, 401000 <banchMark2+0x180>
  400b18:	91086020 	add	x0, x1, #0x218
  400b1c:	aa0203e1 	mov	x1, x2
  400b20:	97fffed4 	bl	400670 <printf@plt>
  400b24:	12800000 	mov	w0, #0xffffffff            	// #-1
  400b28:	17ffffec 	b	400ad8 <priv_ao_copy_inter2plan2+0xf8>
  400b2c:	d503201f 	nop

0000000000400b30 <priv_ao_copy_inter2plan3>:
  400b30:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  400b34:	f100001f 	cmp	x0, #0x0
  400b38:	fa401864 	ccmp	x3, #0x0, #0x4, ne  // ne = any
  400b3c:	910003fd 	mov	x29, sp
  400b40:	54000680 	b.eq	400c10 <priv_ao_copy_inter2plan3+0xe0>  // b.none
  400b44:	7100405f 	cmp	w2, #0x10
  400b48:	540005a1 	b.ne	400bfc <priv_ao_copy_inter2plan3+0xcc>  // b.any
  400b4c:	eb03001f 	cmp	x0, x3
  400b50:	53017c27 	lsr	w7, w1, #1
  400b54:	540006c0 	b.eq	400c2c <priv_ao_copy_inter2plan3+0xfc>  // b.none
  400b58:	8b214066 	add	x6, x3, w1, uxtw
  400b5c:	120004e7 	and	w7, w7, #0x3
  400b60:	53037c21 	lsr	w1, w1, #3
  400b64:	34000481 	cbz	w1, 400bf4 <priv_ao_copy_inter2plan3+0xc4>
  400b68:	d37c7024 	ubfiz	x4, x1, #4, #29
  400b6c:	2a0103e5 	mov	w5, w1
  400b70:	8b040004 	add	x4, x0, x4
  400b74:	aa0603e2 	mov	x2, x6
  400b78:	aa0303e1 	mov	x1, x3
  400b7c:	d503201f 	nop
__attribute__ ((__always_inline__, __gnu_inline__, __artificial__))
vld2_s16 (const int16_t * __a)
{
  int16x4x2_t ret;
  __builtin_aarch64_simd_oi __o;
  __o = __builtin_aarch64_ld2v4hi ((const __builtin_aarch64_simd_hi *) __a);
  400b80:	0c408400 	ld2	{v0.4h, v1.4h}, [x0]
  400b84:	91004000 	add	x0, x0, #0x10
  400b88:	eb04001f 	cmp	x0, x4

__extension__ extern __inline void
__attribute__ ((__always_inline__, __gnu_inline__, __artificial__))
vst1_s16 (int16_t *__a, int16x4_t __b)
{
  __builtin_aarch64_st1v4hi ((__builtin_aarch64_simd_hi *) __a, __b);
  400b8c:	fc008420 	str	d0, [x1], #8
  400b90:	fc008441 	str	d1, [x2], #8
  400b94:	54ffff61 	b.ne	400b80 <priv_ao_copy_inter2plan3+0x50>  // b.any
  400b98:	d37df0a1 	lsl	x1, x5, #3
  400b9c:	8b010063 	add	x3, x3, x1
  400ba0:	8b0100c6 	add	x6, x6, x1
  400ba4:	34000227 	cbz	w7, 400be8 <priv_ao_copy_inter2plan3+0xb8>
  400ba8:	79c00080 	ldrsh	w0, [x4]
  400bac:	710004ff 	cmp	w7, #0x1
  400bb0:	79000060 	strh	w0, [x3]
  400bb4:	79c00480 	ldrsh	w0, [x4, #2]
  400bb8:	790000c0 	strh	w0, [x6]
  400bbc:	54000160 	b.eq	400be8 <priv_ao_copy_inter2plan3+0xb8>  // b.none
  400bc0:	79c00880 	ldrsh	w0, [x4, #4]
  400bc4:	710008ff 	cmp	w7, #0x2
  400bc8:	79000460 	strh	w0, [x3, #2]
  400bcc:	79c00c80 	ldrsh	w0, [x4, #6]
  400bd0:	790004c0 	strh	w0, [x6, #2]
  400bd4:	540000a0 	b.eq	400be8 <priv_ao_copy_inter2plan3+0xb8>  // b.none
  400bd8:	79c01080 	ldrsh	w0, [x4, #8]
  400bdc:	79000860 	strh	w0, [x3, #4]
  400be0:	79c01480 	ldrsh	w0, [x4, #10]
  400be4:	790008c0 	strh	w0, [x6, #4]
  400be8:	52800000 	mov	w0, #0x0                   	// #0
  400bec:	a8c17bfd 	ldp	x29, x30, [sp], #16
  400bf0:	d65f03c0 	ret
  400bf4:	aa0003e4 	mov	x4, x0
  400bf8:	17ffffeb 	b	400ba4 <priv_ao_copy_inter2plan3+0x74>
  400bfc:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400c00:	910a2000 	add	x0, x0, #0x288
  400c04:	97fffe9b 	bl	400670 <printf@plt>
  400c08:	12800000 	mov	w0, #0xffffffff            	// #-1
  400c0c:	17fffff8 	b	400bec <priv_ao_copy_inter2plan3+0xbc>
  400c10:	aa0003e1 	mov	x1, x0
  400c14:	aa0303e2 	mov	x2, x3
  400c18:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400c1c:	91066000 	add	x0, x0, #0x198
  400c20:	97fffe94 	bl	400670 <printf@plt>
  400c24:	12800000 	mov	w0, #0xffffffff            	// #-1
  400c28:	17fffff1 	b	400bec <priv_ao_copy_inter2plan3+0xbc>
  400c2c:	aa0003e2 	mov	x2, x0
  400c30:	b0000001 	adrp	x1, 401000 <banchMark2+0x180>
  400c34:	91086020 	add	x0, x1, #0x218
  400c38:	aa0203e1 	mov	x1, x2
  400c3c:	97fffe8d 	bl	400670 <printf@plt>
  400c40:	12800000 	mov	w0, #0xffffffff            	// #-1
  400c44:	17ffffea 	b	400bec <priv_ao_copy_inter2plan3+0xbc>
  400c48:	d503201f 	nop
  400c4c:	d503201f 	nop

0000000000400c50 <banchMark>:
  400c50:	a9bc7bfd 	stp	x29, x30, [sp, #-64]!
  400c54:	d280a000 	mov	x0, #0x500                 	// #1280
  400c58:	910003fd 	mov	x29, sp
  400c5c:	a90153f3 	stp	x19, x20, [sp, #16]
  400c60:	a9025bf5 	stp	x21, x22, [sp, #32]
  400c64:	97fffe77 	bl	400640 <malloc@plt>
  400c68:	aa0003f3 	mov	x19, x0
  400c6c:	d280a000 	mov	x0, #0x500                 	// #1280
  400c70:	97fffe74 	bl	400640 <malloc@plt>
  400c74:	d280a002 	mov	x2, #0x500                 	// #1280
  400c78:	aa0003f4 	mov	x20, x0
  400c7c:	52801561 	mov	w1, #0xab                  	// #171
  400c80:	97fffe68 	bl	400620 <memset@plt>
  400c84:	aa1303e0 	mov	x0, x19
  400c88:	d280a002 	mov	x2, #0x500                 	// #1280
  400c8c:	52800001 	mov	w1, #0x0                   	// #0
  400c90:	97fffe64 	bl	400620 <memset@plt>
  400c94:	aa1303e3 	mov	x3, x19
  400c98:	aa1403e0 	mov	x0, x20
  400c9c:	52800202 	mov	w2, #0x10                  	// #16
  400ca0:	52805001 	mov	w1, #0x280                 	// #640
  400ca4:	b9003fff 	str	wzr, [sp, #60]
  400ca8:	97fffece 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400cac:	d53be056 	mrs	x22, cntvct_el0
  400cb0:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400cb4:	d503201f 	nop
  400cb8:	52805001 	mov	w1, #0x280                 	// #640
  400cbc:	aa1303e3 	mov	x3, x19
  400cc0:	aa1403e0 	mov	x0, x20
  400cc4:	52800202 	mov	w2, #0x10                  	// #16
  400cc8:	97fffec6 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400ccc:	b9403fe1 	ldr	w1, [sp, #60]
  400cd0:	710006b5 	subs	w21, w21, #0x1
  400cd4:	39400260 	ldrb	w0, [x19]
  400cd8:	0b010000 	add	w0, w0, w1
  400cdc:	b9003fe0 	str	w0, [sp, #60]
  400ce0:	54fffec1 	b.ne	400cb8 <banchMark+0x68>  // b.any
  400ce4:	d53be041 	mrs	x1, cntvct_el0
  400ce8:	cb160021 	sub	x1, x1, x22
  400cec:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400cf0:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400cf4:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400cf8:	910ae000 	add	x0, x0, #0x2b8
  400cfc:	d343fc21 	lsr	x1, x1, #3
  400d00:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400d04:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400d08:	9bc27c21 	umulh	x1, x1, x2
  400d0c:	d344fc21 	lsr	x1, x1, #4
  400d10:	97fffe58 	bl	400670 <printf@plt>
  400d14:	d53be056 	mrs	x22, cntvct_el0
  400d18:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400d1c:	d503201f 	nop
  400d20:	52805001 	mov	w1, #0x280                 	// #640
  400d24:	aa1303e3 	mov	x3, x19
  400d28:	aa1403e0 	mov	x0, x20
  400d2c:	52800202 	mov	w2, #0x10                  	// #16
  400d30:	97fffef0 	bl	4008f0 <priv_ao_copy_inter2plan1>
  400d34:	b9403fe1 	ldr	w1, [sp, #60]
  400d38:	710006b5 	subs	w21, w21, #0x1
  400d3c:	39400260 	ldrb	w0, [x19]
  400d40:	0b010000 	add	w0, w0, w1
  400d44:	b9003fe0 	str	w0, [sp, #60]
  400d48:	54fffec1 	b.ne	400d20 <banchMark+0xd0>  // b.any
  400d4c:	d53be041 	mrs	x1, cntvct_el0
  400d50:	cb160021 	sub	x1, x1, x22
  400d54:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400d58:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400d5c:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400d60:	910b8000 	add	x0, x0, #0x2e0
  400d64:	d343fc21 	lsr	x1, x1, #3
  400d68:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400d6c:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400d70:	9bc27c21 	umulh	x1, x1, x2
  400d74:	d344fc21 	lsr	x1, x1, #4
  400d78:	97fffe3e 	bl	400670 <printf@plt>
  400d7c:	d53be056 	mrs	x22, cntvct_el0
  400d80:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400d84:	d503201f 	nop
  400d88:	52805001 	mov	w1, #0x280                 	// #640
  400d8c:	aa1303e3 	mov	x3, x19
  400d90:	aa1403e0 	mov	x0, x20
  400d94:	52800202 	mov	w2, #0x10                  	// #16
  400d98:	97ffff12 	bl	4009e0 <priv_ao_copy_inter2plan2>
  400d9c:	b9403fe1 	ldr	w1, [sp, #60]
  400da0:	710006b5 	subs	w21, w21, #0x1
  400da4:	39400260 	ldrb	w0, [x19]
  400da8:	0b010000 	add	w0, w0, w1
  400dac:	b9003fe0 	str	w0, [sp, #60]
  400db0:	54fffec1 	b.ne	400d88 <banchMark+0x138>  // b.any
  400db4:	d53be041 	mrs	x1, cntvct_el0
  400db8:	cb160021 	sub	x1, x1, x22
  400dbc:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400dc0:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400dc4:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400dc8:	910c2000 	add	x0, x0, #0x308
  400dcc:	d343fc21 	lsr	x1, x1, #3
  400dd0:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400dd4:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400dd8:	9bc27c21 	umulh	x1, x1, x2
  400ddc:	d344fc21 	lsr	x1, x1, #4
  400de0:	97fffe24 	bl	400670 <printf@plt>
  400de4:	d53be056 	mrs	x22, cntvct_el0
  400de8:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400dec:	d503201f 	nop
  400df0:	52805001 	mov	w1, #0x280                 	// #640
  400df4:	aa1303e3 	mov	x3, x19
  400df8:	aa1403e0 	mov	x0, x20
  400dfc:	52800202 	mov	w2, #0x10                  	// #16
  400e00:	97ffff4c 	bl	400b30 <priv_ao_copy_inter2plan3>
  400e04:	b9403fe1 	ldr	w1, [sp, #60]
  400e08:	710006b5 	subs	w21, w21, #0x1
  400e0c:	39400260 	ldrb	w0, [x19]
  400e10:	0b010000 	add	w0, w0, w1
  400e14:	b9003fe0 	str	w0, [sp, #60]
  400e18:	54fffec1 	b.ne	400df0 <banchMark+0x1a0>  // b.any
  400e1c:	d53be041 	mrs	x1, cntvct_el0
  400e20:	cb160021 	sub	x1, x1, x22
  400e24:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400e28:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400e2c:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400e30:	910cc000 	add	x0, x0, #0x330
  400e34:	d343fc21 	lsr	x1, x1, #3
  400e38:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400e3c:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400e40:	9bc27c21 	umulh	x1, x1, x2
  400e44:	d344fc21 	lsr	x1, x1, #4
  400e48:	97fffe0a 	bl	400670 <printf@plt>
  400e4c:	b9403fe1 	ldr	w1, [sp, #60]
  400e50:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400e54:	910d6000 	add	x0, x0, #0x358
  400e58:	97fffe06 	bl	400670 <printf@plt>
  400e5c:	aa1303e0 	mov	x0, x19
  400e60:	97fffdec 	bl	400610 <free@plt>
  400e64:	aa1403e0 	mov	x0, x20
  400e68:	a94153f3 	ldp	x19, x20, [sp, #16]
  400e6c:	a9425bf5 	ldp	x21, x22, [sp, #32]
  400e70:	a8c47bfd 	ldp	x29, x30, [sp], #64
  400e74:	17fffde7 	b	400610 <free@plt>
  400e78:	d503201f 	nop
  400e7c:	d503201f 	nop

0000000000400e80 <banchMark2>:
  400e80:	a9bb7bfd 	stp	x29, x30, [sp, #-80]!
  400e84:	d280a000 	mov	x0, #0x500                 	// #1280
  400e88:	910003fd 	mov	x29, sp
  400e8c:	a90153f3 	stp	x19, x20, [sp, #16]
  400e90:	a9025bf5 	stp	x21, x22, [sp, #32]
  400e94:	f9001bf7 	str	x23, [sp, #48]
  400e98:	fd001fe8 	str	d8, [sp, #56]
  400e9c:	97fffde9 	bl	400640 <malloc@plt>
  400ea0:	aa0003f3 	mov	x19, x0
  400ea4:	d280a000 	mov	x0, #0x500                 	// #1280
  400ea8:	97fffde6 	bl	400640 <malloc@plt>
  400eac:	aa0003f4 	mov	x20, x0
  400eb0:	d280a002 	mov	x2, #0x500                 	// #1280
  400eb4:	52801561 	mov	w1, #0xab                  	// #171
  400eb8:	97fffdda 	bl	400620 <memset@plt>
  400ebc:	aa1303e0 	mov	x0, x19
  400ec0:	d280a002 	mov	x2, #0x500                 	// #1280
  400ec4:	52800001 	mov	w1, #0x0                   	// #0
  400ec8:	97fffdd6 	bl	400620 <memset@plt>
  400ecc:	b9004fff 	str	wzr, [sp, #76]
  400ed0:	d53be016 	mrs	x22, cntfrq_el0
  400ed4:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400ed8:	aa1603e1 	mov	x1, x22
  400edc:	910de000 	add	x0, x0, #0x378
  400ee0:	97fffde4 	bl	400670 <printf@plt>
  400ee4:	aa1303e3 	mov	x3, x19
  400ee8:	aa1403e0 	mov	x0, x20
  400eec:	52800202 	mov	w2, #0x10                  	// #16
  400ef0:	52805001 	mov	w1, #0x280                 	// #640
  400ef4:	97fffe3b 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400ef8:	d53be057 	mrs	x23, cntvct_el0
  400efc:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400f00:	52805001 	mov	w1, #0x280                 	// #640
  400f04:	aa1303e3 	mov	x3, x19
  400f08:	aa1403e0 	mov	x0, x20
  400f0c:	52800202 	mov	w2, #0x10                  	// #16
  400f10:	97fffe34 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400f14:	b9404fe1 	ldr	w1, [sp, #76]
  400f18:	710006b5 	subs	w21, w21, #0x1
  400f1c:	39400260 	ldrb	w0, [x19]
  400f20:	0b010000 	add	w0, w0, w1
  400f24:	b9004fe0 	str	w0, [sp, #76]
  400f28:	54fffec1 	b.ne	400f00 <banchMark2+0x80>  // b.any
  400f2c:	d53be040 	mrs	x0, cntvct_el0
  400f30:	cb170000 	sub	x0, x0, x23
  400f34:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  400f38:	f2e825c1 	movk	x1, #0x412e, lsl #48
  400f3c:	9e670022 	fmov	d2, x1
  400f40:	9e630000 	ucvtf	d0, x0
  400f44:	9e6302c8 	ucvtf	d8, x22
  400f48:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  400f4c:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400f50:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400f54:	f2e811e1 	movk	x1, #0x408f, lsl #48
  400f58:	9e670021 	fmov	d1, x1
  400f5c:	d343fc01 	lsr	x1, x0, #3
  400f60:	1e620800 	fmul	d0, d0, d2
  400f64:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400f68:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400f6c:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400f70:	910e8000 	add	x0, x0, #0x3a0
  400f74:	9bc27c21 	umulh	x1, x1, x2
  400f78:	1e681800 	fdiv	d0, d0, d8
  400f7c:	d344fc21 	lsr	x1, x1, #4
  400f80:	1e611800 	fdiv	d0, d0, d1
  400f84:	97fffdbb 	bl	400670 <printf@plt>
  400f88:	d53be056 	mrs	x22, cntvct_el0
  400f8c:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400f90:	52805001 	mov	w1, #0x280                 	// #640
  400f94:	aa1303e3 	mov	x3, x19
  400f98:	aa1403e0 	mov	x0, x20
  400f9c:	52800202 	mov	w2, #0x10                  	// #16
  400fa0:	97fffe54 	bl	4008f0 <priv_ao_copy_inter2plan1>
  400fa4:	b9404fe1 	ldr	w1, [sp, #76]
  400fa8:	710006b5 	subs	w21, w21, #0x1
  400fac:	39400260 	ldrb	w0, [x19]
  400fb0:	0b010000 	add	w0, w0, w1
  400fb4:	b9004fe0 	str	w0, [sp, #76]
  400fb8:	54fffec1 	b.ne	400f90 <banchMark2+0x110>  // b.any
  400fbc:	d53be040 	mrs	x0, cntvct_el0
  400fc0:	cb160000 	sub	x0, x0, x22
  400fc4:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  400fc8:	f2e825c1 	movk	x1, #0x412e, lsl #48
  400fcc:	9e670022 	fmov	d2, x1
  400fd0:	9e630000 	ucvtf	d0, x0
  400fd4:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  400fd8:	f2e811e1 	movk	x1, #0x408f, lsl #48
  400fdc:	9e670021 	fmov	d1, x1
  400fe0:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400fe4:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400fe8:	d343fc01 	lsr	x1, x0, #3
  400fec:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400ff0:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400ff4:	1e620800 	fmul	d0, d0, d2
  400ff8:	b0000000 	adrp	x0, 401000 <banchMark2+0x180>
  400ffc:	910f6000 	add	x0, x0, #0x3d8
  401000:	9bc27c21 	umulh	x1, x1, x2
  401004:	1e681800 	fdiv	d0, d0, d8
  401008:	d344fc21 	lsr	x1, x1, #4
  40100c:	1e611800 	fdiv	d0, d0, d1
  401010:	97fffd98 	bl	400670 <printf@plt>
  401014:	d53be056 	mrs	x22, cntvct_el0
  401018:	52807d15 	mov	w21, #0x3e8                 	// #1000
  40101c:	d503201f 	nop
  401020:	52805001 	mov	w1, #0x280                 	// #640
  401024:	aa1303e3 	mov	x3, x19
  401028:	aa1403e0 	mov	x0, x20
  40102c:	52800202 	mov	w2, #0x10                  	// #16
  401030:	97fffe6c 	bl	4009e0 <priv_ao_copy_inter2plan2>
  401034:	b9404fe1 	ldr	w1, [sp, #76]
  401038:	710006b5 	subs	w21, w21, #0x1
  40103c:	39400260 	ldrb	w0, [x19]
  401040:	0b010000 	add	w0, w0, w1
  401044:	b9004fe0 	str	w0, [sp, #76]
  401048:	54fffec1 	b.ne	401020 <banchMark2+0x1a0>  // b.any
  40104c:	d53be040 	mrs	x0, cntvct_el0
  401050:	cb160000 	sub	x0, x0, x22
  401054:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  401058:	f2e825c1 	movk	x1, #0x412e, lsl #48
  40105c:	9e670022 	fmov	d2, x1
  401060:	9e630000 	ucvtf	d0, x0
  401064:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  401068:	f2e811e1 	movk	x1, #0x408f, lsl #48
  40106c:	9e670021 	fmov	d1, x1
  401070:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  401074:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  401078:	d343fc01 	lsr	x1, x0, #3
  40107c:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  401080:	f2e41882 	movk	x2, #0x20c4, lsl #48
  401084:	1e620800 	fmul	d0, d0, d2
  401088:	90000000 	adrp	x0, 401000 <banchMark2+0x180>
  40108c:	91104000 	add	x0, x0, #0x410
  401090:	9bc27c21 	umulh	x1, x1, x2
  401094:	1e681800 	fdiv	d0, d0, d8
  401098:	d344fc21 	lsr	x1, x1, #4
  40109c:	1e611800 	fdiv	d0, d0, d1
  4010a0:	97fffd74 	bl	400670 <printf@plt>
  4010a4:	d53be056 	mrs	x22, cntvct_el0
  4010a8:	52807d15 	mov	w21, #0x3e8                 	// #1000
  4010ac:	d503201f 	nop
  4010b0:	52805001 	mov	w1, #0x280                 	// #640
  4010b4:	aa1303e3 	mov	x3, x19
  4010b8:	aa1403e0 	mov	x0, x20
  4010bc:	52800202 	mov	w2, #0x10                  	// #16
  4010c0:	97fffe9c 	bl	400b30 <priv_ao_copy_inter2plan3>
  4010c4:	b9404fe1 	ldr	w1, [sp, #76]
  4010c8:	710006b5 	subs	w21, w21, #0x1
  4010cc:	39400260 	ldrb	w0, [x19]
  4010d0:	0b010000 	add	w0, w0, w1
  4010d4:	b9004fe0 	str	w0, [sp, #76]
  4010d8:	54fffec1 	b.ne	4010b0 <banchMark2+0x230>  // b.any
  4010dc:	d53be040 	mrs	x0, cntvct_el0
  4010e0:	cb160000 	sub	x0, x0, x22
  4010e4:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  4010e8:	f2e825c1 	movk	x1, #0x412e, lsl #48
  4010ec:	9e670022 	fmov	d2, x1
  4010f0:	9e630000 	ucvtf	d0, x0
  4010f4:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  4010f8:	f2e811e1 	movk	x1, #0x408f, lsl #48
  4010fc:	9e670021 	fmov	d1, x1
  401100:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  401104:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  401108:	d343fc01 	lsr	x1, x0, #3
  40110c:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  401110:	f2e41882 	movk	x2, #0x20c4, lsl #48
  401114:	1e620800 	fmul	d0, d0, d2
  401118:	90000000 	adrp	x0, 401000 <banchMark2+0x180>
  40111c:	91112000 	add	x0, x0, #0x448
  401120:	9bc27c21 	umulh	x1, x1, x2
  401124:	1e681800 	fdiv	d0, d0, d8
  401128:	d344fc21 	lsr	x1, x1, #4
  40112c:	1e611800 	fdiv	d0, d0, d1
  401130:	97fffd50 	bl	400670 <printf@plt>
  401134:	b9404fe1 	ldr	w1, [sp, #76]
  401138:	90000000 	adrp	x0, 401000 <banchMark2+0x180>
  40113c:	910d6000 	add	x0, x0, #0x358
  401140:	97fffd4c 	bl	400670 <printf@plt>
  401144:	aa1303e0 	mov	x0, x19
  401148:	97fffd32 	bl	400610 <free@plt>
  40114c:	aa1403e0 	mov	x0, x20
  401150:	fd401fe8 	ldr	d8, [sp, #56]
  401154:	a94153f3 	ldp	x19, x20, [sp, #16]
  401158:	a9425bf5 	ldp	x21, x22, [sp, #32]
  40115c:	f9401bf7 	ldr	x23, [sp, #48]
  401160:	a8c57bfd 	ldp	x29, x30, [sp], #80
  401164:	17fffd2b 	b	400610 <free@plt>

Disassembly of section .fini:

0000000000401168 <_fini>:
  401168:	d503201f 	nop
  40116c:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  401170:	910003fd 	mov	x29, sp
  401174:	a8c17bfd 	ldp	x29, x30, [sp], #16
  401178:	d65f03c0 	ret
