
app-O3-ftree:     file format elf64-littleaarch64


Disassembly of section .init:

00000000004005c8 <_init>:
  4005c8:	d503201f 	nop
  4005cc:	a9bf7bfd 	stp	x29, x30, [sp,#-16]!
  4005d0:	910003fd 	mov	x29, sp
  4005d4:	9400004b 	bl	400700 <call_weak_fn>
  4005d8:	a8c17bfd 	ldp	x29, x30, [sp],#16
  4005dc:	d65f03c0 	ret

Disassembly of section .plt:

00000000004005e0 <memcpy@plt-0x20>:
  4005e0:	a9bf7bf0 	stp	x16, x30, [sp,#-16]!
  4005e4:	b0000090 	adrp	x16, 411000 <__FRAME_END__+0xf7f0>
  4005e8:	f947fe11 	ldr	x17, [x16,#4088]
  4005ec:	913fe210 	add	x16, x16, #0xff8
  4005f0:	d61f0220 	br	x17
  4005f4:	d503201f 	nop
  4005f8:	d503201f 	nop
  4005fc:	d503201f 	nop

0000000000400600 <memcpy@plt>:
  400600:	d0000090 	adrp	x16, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400604:	f9400211 	ldr	x17, [x16]
  400608:	91000210 	add	x16, x16, #0x0
  40060c:	d61f0220 	br	x17

0000000000400610 <free@plt>:
  400610:	d0000090 	adrp	x16, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400614:	f9400611 	ldr	x17, [x16,#8]
  400618:	91002210 	add	x16, x16, #0x8
  40061c:	d61f0220 	br	x17

0000000000400620 <memset@plt>:
  400620:	d0000090 	adrp	x16, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400624:	f9400a11 	ldr	x17, [x16,#16]
  400628:	91004210 	add	x16, x16, #0x10
  40062c:	d61f0220 	br	x17

0000000000400630 <__libc_start_main@plt>:
  400630:	d0000090 	adrp	x16, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400634:	f9400e11 	ldr	x17, [x16,#24]
  400638:	91006210 	add	x16, x16, #0x18
  40063c:	d61f0220 	br	x17

0000000000400640 <malloc@plt>:
  400640:	d0000090 	adrp	x16, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400644:	f9401211 	ldr	x17, [x16,#32]
  400648:	91008210 	add	x16, x16, #0x20
  40064c:	d61f0220 	br	x17

0000000000400650 <abort@plt>:
  400650:	d0000090 	adrp	x16, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400654:	f9401611 	ldr	x17, [x16,#40]
  400658:	9100a210 	add	x16, x16, #0x28
  40065c:	d61f0220 	br	x17

0000000000400660 <__gmon_start__@plt>:
  400660:	d0000090 	adrp	x16, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400664:	f9401a11 	ldr	x17, [x16,#48]
  400668:	9100c210 	add	x16, x16, #0x30
  40066c:	d61f0220 	br	x17

0000000000400670 <printf@plt>:
  400670:	d0000090 	adrp	x16, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400674:	f9401e11 	ldr	x17, [x16,#56]
  400678:	9100e210 	add	x16, x16, #0x38
  40067c:	d61f0220 	br	x17

Disassembly of section .text:

0000000000400680 <main>:
  400680:	a9bf7bfd 	stp	x29, x30, [sp,#-16]!
  400684:	910003fd 	mov	x29, sp
  400688:	940001ae 	bl	400d40 <banchMark>
  40068c:	94000239 	bl	400f70 <banchMark2>
  400690:	52800000 	mov	w0, #0x0                   	// #0
  400694:	a8c17bfd 	ldp	x29, x30, [sp],#16
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
  400700:	b0000080 	adrp	x0, 411000 <__FRAME_END__+0xf7f0>
  400704:	f947f000 	ldr	x0, [x0,#4064]
  400708:	b4000040 	cbz	x0, 400710 <call_weak_fn+0x10>
  40070c:	17ffffd5 	b	400660 <__gmon_start__@plt>
  400710:	d65f03c0 	ret

0000000000400714 <deregister_tm_clones>:
  400714:	d0000080 	adrp	x0, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400718:	91014001 	add	x1, x0, #0x50
  40071c:	d0000080 	adrp	x0, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400720:	91014000 	add	x0, x0, #0x50
  400724:	eb00003f 	cmp	x1, x0
  400728:	54000160 	b.eq	400754 <deregister_tm_clones+0x40>
  40072c:	d10043ff 	sub	sp, sp, #0x10
  400730:	b0000001 	adrp	x1, 401000 <banchMark2+0x90>
  400734:	f9413c21 	ldr	x1, [x1,#632]
  400738:	f90007e1 	str	x1, [sp,#8]
  40073c:	b4000081 	cbz	x1, 40074c <deregister_tm_clones+0x38>
  400740:	aa0103f0 	mov	x16, x1
  400744:	910043ff 	add	sp, sp, #0x10
  400748:	d61f0200 	br	x16
  40074c:	910043ff 	add	sp, sp, #0x10
  400750:	d65f03c0 	ret
  400754:	d65f03c0 	ret

0000000000400758 <register_tm_clones>:
  400758:	d0000080 	adrp	x0, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  40075c:	91014001 	add	x1, x0, #0x50
  400760:	d0000080 	adrp	x0, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  400764:	91014000 	add	x0, x0, #0x50
  400768:	cb000021 	sub	x1, x1, x0
  40076c:	d2800042 	mov	x2, #0x2                   	// #2
  400770:	9343fc21 	asr	x1, x1, #3
  400774:	9ac20c21 	sdiv	x1, x1, x2
  400778:	b4000161 	cbz	x1, 4007a4 <register_tm_clones+0x4c>
  40077c:	d10043ff 	sub	sp, sp, #0x10
  400780:	b0000002 	adrp	x2, 401000 <banchMark2+0x90>
  400784:	f9414042 	ldr	x2, [x2,#640]
  400788:	f90007e2 	str	x2, [sp,#8]
  40078c:	b4000082 	cbz	x2, 40079c <register_tm_clones+0x44>
  400790:	aa0203f0 	mov	x16, x2
  400794:	910043ff 	add	sp, sp, #0x10
  400798:	d61f0200 	br	x16
  40079c:	910043ff 	add	sp, sp, #0x10
  4007a0:	d65f03c0 	ret
  4007a4:	d65f03c0 	ret

00000000004007a8 <__do_global_dtors_aux>:
  4007a8:	a9be7bfd 	stp	x29, x30, [sp,#-32]!
  4007ac:	910003fd 	mov	x29, sp
  4007b0:	f9000bf3 	str	x19, [sp,#16]
  4007b4:	d0000093 	adrp	x19, 412000 <_GLOBAL_OFFSET_TABLE_+0x28>
  4007b8:	39414260 	ldrb	w0, [x19,#80]
  4007bc:	35000080 	cbnz	w0, 4007cc <__do_global_dtors_aux+0x24>
  4007c0:	97ffffd5 	bl	400714 <deregister_tm_clones>
  4007c4:	52800020 	mov	w0, #0x1                   	// #1
  4007c8:	39014260 	strb	w0, [x19,#80]
  4007cc:	f9400bf3 	ldr	x19, [sp,#16]
  4007d0:	a8c27bfd 	ldp	x29, x30, [sp],#32
  4007d4:	d65f03c0 	ret

00000000004007d8 <frame_dummy>:
  4007d8:	17ffffe0 	b	400758 <register_tm_clones>
  4007dc:	d503201f 	nop

00000000004007e0 <priv_ao_copy_inter2plan0>:
  4007e0:	a9ba7bfd 	stp	x29, x30, [sp,#-96]!
  4007e4:	f100001f 	cmp	x0, #0x0
  4007e8:	fa401864 	ccmp	x3, #0x0, #0x4, ne
  4007ec:	910003fd 	mov	x29, sp
  4007f0:	a9025bf5 	stp	x21, x22, [sp,#32]
  4007f4:	aa0003f6 	mov	x22, x0
  4007f8:	a90363f7 	stp	x23, x24, [sp,#48]
  4007fc:	aa0303f7 	mov	x23, x3
  400800:	54000580 	b.eq	4008b0 <priv_ao_copy_inter2plan0+0xd0>
  400804:	53037c58 	lsr	w24, w2, #3
  400808:	a9046bf9 	stp	x25, x26, [sp,#64]
  40080c:	2a0103f9 	mov	w25, w1
  400810:	1ad80822 	udiv	w2, w1, w24
  400814:	1b027f00 	mul	w0, w24, w2
  400818:	6b01001f 	cmp	w0, w1
  40081c:	54000403 	b.cc	40089c <priv_ao_copy_inter2plan0+0xbc>
  400820:	eb1702df 	cmp	x22, x23
  400824:	54000540 	b.eq	4008cc <priv_ao_copy_inter2plan0+0xec>
  400828:	a90153f3 	stp	x19, x20, [sp,#16]
  40082c:	2a1903fa 	mov	w26, w25
  400830:	52800013 	mov	w19, #0x0                   	// #0
  400834:	f9002bfb 	str	x27, [sp,#80]
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
  400878:	54fffe48 	b.hi	400840 <priv_ao_copy_inter2plan0+0x60>
  40087c:	a94153f3 	ldp	x19, x20, [sp,#16]
  400880:	52800000 	mov	w0, #0x0                   	// #0
  400884:	a9446bf9 	ldp	x25, x26, [sp,#64]
  400888:	f9402bfb 	ldr	x27, [sp,#80]
  40088c:	a9425bf5 	ldp	x21, x22, [sp,#32]
  400890:	a94363f7 	ldp	x23, x24, [sp,#48]
  400894:	a8c67bfd 	ldp	x29, x30, [sp],#96
  400898:	d65f03c0 	ret
  40089c:	2a1803e3 	mov	w3, w24
  4008a0:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  4008a4:	910ae000 	add	x0, x0, #0x2b8
  4008a8:	97ffff72 	bl	400670 <printf@plt>
  4008ac:	17ffffdd 	b	400820 <priv_ao_copy_inter2plan0+0x40>
  4008b0:	aa0003e1 	mov	x1, x0
  4008b4:	aa0303e2 	mov	x2, x3
  4008b8:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  4008bc:	910a2000 	add	x0, x0, #0x288
  4008c0:	97ffff6c 	bl	400670 <printf@plt>
  4008c4:	12800000 	mov	w0, #0xffffffff            	// #-1
  4008c8:	17fffff1 	b	40088c <priv_ao_copy_inter2plan0+0xac>
  4008cc:	aa1603e2 	mov	x2, x22
  4008d0:	aa1603e1 	mov	x1, x22
  4008d4:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  4008d8:	910c2000 	add	x0, x0, #0x308
  4008dc:	97ffff65 	bl	400670 <printf@plt>
  4008e0:	12800000 	mov	w0, #0xffffffff            	// #-1
  4008e4:	a9446bf9 	ldp	x25, x26, [sp,#64]
  4008e8:	17ffffe9 	b	40088c <priv_ao_copy_inter2plan0+0xac>
  4008ec:	d503201f 	nop

00000000004008f0 <priv_ao_copy_inter2plan1>:
  4008f0:	a9bc7bfd 	stp	x29, x30, [sp,#-64]!
  4008f4:	f100001f 	cmp	x0, #0x0
  4008f8:	fa401864 	ccmp	x3, #0x0, #0x4, ne
  4008fc:	910003fd 	mov	x29, sp
  400900:	a90153f3 	stp	x19, x20, [sp,#16]
  400904:	aa0003f3 	mov	x19, x0
  400908:	aa0303f4 	mov	x20, x3
  40090c:	540004a0 	b.eq	4009a0 <priv_ao_copy_inter2plan1+0xb0>
  400910:	a9025bf5 	stp	x21, x22, [sp,#32]
  400914:	53037c56 	lsr	w22, w2, #3
  400918:	f9001bf7 	str	x23, [sp,#48]
  40091c:	2a0103f7 	mov	w23, w1
  400920:	1ad60835 	udiv	w21, w1, w22
  400924:	1b157ec0 	mul	w0, w22, w21
  400928:	6b01001f 	cmp	w0, w1
  40092c:	540002e3 	b.cc	400988 <priv_ao_copy_inter2plan1+0x98>
  400930:	eb14027f 	cmp	x19, x20
  400934:	54000440 	b.eq	4009bc <priv_ao_copy_inter2plan1+0xcc>
  400938:	6b1702df 	cmp	w22, w23
  40093c:	52800004 	mov	w4, #0x0                   	// #0
  400940:	d2800001 	mov	x1, #0x0                   	// #0
  400944:	54000168 	b.hi	400970 <priv_ao_copy_inter2plan1+0x80>
  400948:	78e45a62 	ldrsh	w2, [x19,w4,uxtw #1]
  40094c:	11000485 	add	w5, w4, #0x1
  400950:	0b0102a0 	add	w0, w21, w1
  400954:	78217a82 	strh	w2, [x20,x1,lsl #1]
  400958:	91000421 	add	x1, x1, #0x1
  40095c:	11000884 	add	w4, w4, #0x2
  400960:	78e57a62 	ldrsh	w2, [x19,x5,lsl #1]
  400964:	6b0102bf 	cmp	w21, w1
  400968:	78207a82 	strh	w2, [x20,x0,lsl #1]
  40096c:	54fffee8 	b.hi	400948 <priv_ao_copy_inter2plan1+0x58>
  400970:	a9425bf5 	ldp	x21, x22, [sp,#32]
  400974:	52800000 	mov	w0, #0x0                   	// #0
  400978:	f9401bf7 	ldr	x23, [sp,#48]
  40097c:	a94153f3 	ldp	x19, x20, [sp,#16]
  400980:	a8c47bfd 	ldp	x29, x30, [sp],#64
  400984:	d65f03c0 	ret
  400988:	2a1603e3 	mov	w3, w22
  40098c:	2a1503e2 	mov	w2, w21
  400990:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400994:	910ae000 	add	x0, x0, #0x2b8
  400998:	97ffff36 	bl	400670 <printf@plt>
  40099c:	17ffffe5 	b	400930 <priv_ao_copy_inter2plan1+0x40>
  4009a0:	aa0003e1 	mov	x1, x0
  4009a4:	aa0303e2 	mov	x2, x3
  4009a8:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  4009ac:	910a2000 	add	x0, x0, #0x288
  4009b0:	97ffff30 	bl	400670 <printf@plt>
  4009b4:	12800000 	mov	w0, #0xffffffff            	// #-1
  4009b8:	17fffff1 	b	40097c <priv_ao_copy_inter2plan1+0x8c>
  4009bc:	aa1303e2 	mov	x2, x19
  4009c0:	aa1303e1 	mov	x1, x19
  4009c4:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  4009c8:	910c2000 	add	x0, x0, #0x308
  4009cc:	97ffff29 	bl	400670 <printf@plt>
  4009d0:	12800000 	mov	w0, #0xffffffff            	// #-1
  4009d4:	a9425bf5 	ldp	x21, x22, [sp,#32]
  4009d8:	f9401bf7 	ldr	x23, [sp,#48]
  4009dc:	17ffffe8 	b	40097c <priv_ao_copy_inter2plan1+0x8c>

00000000004009e0 <priv_ao_copy_inter2plan2>:
  4009e0:	a9bf7bfd 	stp	x29, x30, [sp,#-16]!
  4009e4:	f100001f 	cmp	x0, #0x0
  4009e8:	fa401864 	ccmp	x3, #0x0, #0x4, ne
  4009ec:	910003fd 	mov	x29, sp
  4009f0:	54000fa0 	b.eq	400be4 <priv_ao_copy_inter2plan2+0x204>
  4009f4:	7100405f 	cmp	w2, #0x10
  4009f8:	54000ec1 	b.ne	400bd0 <priv_ao_copy_inter2plan2+0x1f0>
  4009fc:	eb03001f 	cmp	x0, x3
  400a00:	53017c28 	lsr	w8, w1, #1
  400a04:	54000fe0 	b.eq	400c00 <priv_ao_copy_inter2plan2+0x220>
  400a08:	2a0103e2 	mov	w2, w1
  400a0c:	12000508 	and	w8, w8, #0x3
  400a10:	8b020065 	add	x5, x3, x2
  400a14:	53037c27 	lsr	w7, w1, #3
  400a18:	34000807 	cbz	w7, 400b18 <priv_ao_copy_inter2plan2+0x138>
  400a1c:	531d70e4 	lsl	w4, w7, #3
  400a20:	d37c70e6 	ubfiz	x6, x7, #4, #29
  400a24:	8b040042 	add	x2, x2, x4
  400a28:	8b060006 	add	x6, x0, x6
  400a2c:	8b020062 	add	x2, x3, x2
  400a30:	8b040064 	add	x4, x3, x4
  400a34:	eb02001f 	cmp	x0, x2
  400a38:	9100406a 	add	x10, x3, #0x10
  400a3c:	fa4630a2 	ccmp	x5, x6, #0x2, cc
  400a40:	2a0703e9 	mov	w9, w7
  400a44:	1a9f37e2 	cset	w2, cs
  400a48:	eb04001f 	cmp	x0, x4
  400a4c:	fa463062 	ccmp	x3, x6, #0x2, cc
  400a50:	1a9f37eb 	cset	w11, cs
  400a54:	eb0a00bf 	cmp	x5, x10
  400a58:	7a4128e4 	ccmp	w7, #0x1, #0x4, cs
  400a5c:	0a0b0042 	and	w2, w2, w11
  400a60:	1a9f07e4 	cset	w4, ne
  400a64:	6a02009f 	tst	w4, w2
  400a68:	54000800 	b.eq	400b68 <priv_ao_copy_inter2plan2+0x188>
  400a6c:	53047c22 	lsr	w2, w1, #4
  400a70:	aa0003e1 	mov	x1, x0
  400a74:	d2800004 	mov	x4, #0x0                   	// #0
  400a78:	531c6c46 	lsl	w6, w2, #4
  400a7c:	d503201f 	nop
  400a80:	ad400420 	ldp	q0, q1, [x1]
  400a84:	4e411800 	uzp1	v0.8h, v0.8h, v1.8h
  400a88:	3ca46860 	str	q0, [x3,x4]
  400a8c:	ad400420 	ldp	q0, q1, [x1]
  400a90:	91008021 	add	x1, x1, #0x20
  400a94:	4e415800 	uzp2	v0.8h, v0.8h, v1.8h
  400a98:	3ca468a0 	str	q0, [x5,x4]
  400a9c:	91004084 	add	x4, x4, #0x10
  400aa0:	eb06009f 	cmp	x4, x6
  400aa4:	54fffee1 	b.ne	400a80 <priv_ao_copy_inter2plan2+0xa0>
  400aa8:	0b020042 	add	w2, w2, w2
  400aac:	6b0200ff 	cmp	w7, w2
  400ab0:	d37c7047 	ubfiz	x7, x2, #4, #29
  400ab4:	531d7042 	lsl	w2, w2, #3
  400ab8:	8b070001 	add	x1, x0, x7
  400abc:	8b020066 	add	x6, x3, x2
  400ac0:	8b0200a4 	add	x4, x5, x2
  400ac4:	54000220 	b.eq	400b08 <priv_ao_copy_inter2plan2+0x128>
  400ac8:	78e76807 	ldrsh	w7, [x0,x7]
  400acc:	78226867 	strh	w7, [x3,x2]
  400ad0:	79c00427 	ldrsh	w7, [x1,#2]
  400ad4:	782268a7 	strh	w7, [x5,x2]
  400ad8:	79c00822 	ldrsh	w2, [x1,#4]
  400adc:	790004c2 	strh	w2, [x6,#2]
  400ae0:	79c00c22 	ldrsh	w2, [x1,#6]
  400ae4:	79000482 	strh	w2, [x4,#2]
  400ae8:	79c01022 	ldrsh	w2, [x1,#8]
  400aec:	790008c2 	strh	w2, [x6,#4]
  400af0:	79c01422 	ldrsh	w2, [x1,#10]
  400af4:	79000882 	strh	w2, [x4,#4]
  400af8:	79c01822 	ldrsh	w2, [x1,#12]
  400afc:	79000cc2 	strh	w2, [x6,#6]
  400b00:	79c01c21 	ldrsh	w1, [x1,#14]
  400b04:	79000c81 	strh	w1, [x4,#6]
  400b08:	d37df121 	lsl	x1, x9, #3
  400b0c:	8b091000 	add	x0, x0, x9, lsl #4
  400b10:	8b010063 	add	x3, x3, x1
  400b14:	8b0100a5 	add	x5, x5, x1
  400b18:	34000228 	cbz	w8, 400b5c <priv_ao_copy_inter2plan2+0x17c>
  400b1c:	79c00001 	ldrsh	w1, [x0]
  400b20:	7100051f 	cmp	w8, #0x1
  400b24:	79000061 	strh	w1, [x3]
  400b28:	79c00401 	ldrsh	w1, [x0,#2]
  400b2c:	790000a1 	strh	w1, [x5]
  400b30:	54000160 	b.eq	400b5c <priv_ao_copy_inter2plan2+0x17c>
  400b34:	79c00801 	ldrsh	w1, [x0,#4]
  400b38:	7100091f 	cmp	w8, #0x2
  400b3c:	79000461 	strh	w1, [x3,#2]
  400b40:	79c00c01 	ldrsh	w1, [x0,#6]
  400b44:	790004a1 	strh	w1, [x5,#2]
  400b48:	540000a0 	b.eq	400b5c <priv_ao_copy_inter2plan2+0x17c>
  400b4c:	79c01001 	ldrsh	w1, [x0,#8]
  400b50:	79000861 	strh	w1, [x3,#4]
  400b54:	79c01400 	ldrsh	w0, [x0,#10]
  400b58:	790008a0 	strh	w0, [x5,#4]
  400b5c:	52800000 	mov	w0, #0x0                   	// #0
  400b60:	a8c17bfd 	ldp	x29, x30, [sp],#16
  400b64:	d65f03c0 	ret
  400b68:	aa0503e4 	mov	x4, x5
  400b6c:	aa0303e2 	mov	x2, x3
  400b70:	aa0003e1 	mov	x1, x0
  400b74:	d503201f 	nop
  400b78:	79c00027 	ldrsh	w7, [x1]
  400b7c:	91002042 	add	x2, x2, #0x8
  400b80:	781f8047 	sturh	w7, [x2,#-8]
  400b84:	91004021 	add	x1, x1, #0x10
  400b88:	91002084 	add	x4, x4, #0x8
  400b8c:	78df2027 	ldursh	w7, [x1,#-14]
  400b90:	781f8087 	sturh	w7, [x4,#-8]
  400b94:	78df4027 	ldursh	w7, [x1,#-12]
  400b98:	781fa047 	sturh	w7, [x2,#-6]
  400b9c:	78df6027 	ldursh	w7, [x1,#-10]
  400ba0:	781fa087 	sturh	w7, [x4,#-6]
  400ba4:	78df8027 	ldursh	w7, [x1,#-8]
  400ba8:	781fc047 	sturh	w7, [x2,#-4]
  400bac:	78dfa027 	ldursh	w7, [x1,#-6]
  400bb0:	781fc087 	sturh	w7, [x4,#-4]
  400bb4:	78dfc027 	ldursh	w7, [x1,#-4]
  400bb8:	eb06003f 	cmp	x1, x6
  400bbc:	781fe047 	sturh	w7, [x2,#-2]
  400bc0:	78dfe027 	ldursh	w7, [x1,#-2]
  400bc4:	781fe087 	sturh	w7, [x4,#-2]
  400bc8:	54fffd81 	b.ne	400b78 <priv_ao_copy_inter2plan2+0x198>
  400bcc:	17ffffcf 	b	400b08 <priv_ao_copy_inter2plan2+0x128>
  400bd0:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400bd4:	910d2000 	add	x0, x0, #0x348
  400bd8:	97fffea6 	bl	400670 <printf@plt>
  400bdc:	12800000 	mov	w0, #0xffffffff            	// #-1
  400be0:	17ffffe0 	b	400b60 <priv_ao_copy_inter2plan2+0x180>
  400be4:	aa0003e1 	mov	x1, x0
  400be8:	aa0303e2 	mov	x2, x3
  400bec:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400bf0:	910a2000 	add	x0, x0, #0x288
  400bf4:	97fffe9f 	bl	400670 <printf@plt>
  400bf8:	12800000 	mov	w0, #0xffffffff            	// #-1
  400bfc:	17ffffd9 	b	400b60 <priv_ao_copy_inter2plan2+0x180>
  400c00:	aa0003e2 	mov	x2, x0
  400c04:	b0000001 	adrp	x1, 401000 <banchMark2+0x90>
  400c08:	910c2020 	add	x0, x1, #0x308
  400c0c:	aa0203e1 	mov	x1, x2
  400c10:	97fffe98 	bl	400670 <printf@plt>
  400c14:	12800000 	mov	w0, #0xffffffff            	// #-1
  400c18:	17ffffd2 	b	400b60 <priv_ao_copy_inter2plan2+0x180>
  400c1c:	d503201f 	nop

0000000000400c20 <priv_ao_copy_inter2plan3>:
  400c20:	a9bf7bfd 	stp	x29, x30, [sp,#-16]!
  400c24:	f100001f 	cmp	x0, #0x0
  400c28:	fa401864 	ccmp	x3, #0x0, #0x4, ne
  400c2c:	910003fd 	mov	x29, sp
  400c30:	54000680 	b.eq	400d00 <priv_ao_copy_inter2plan3+0xe0>
  400c34:	7100405f 	cmp	w2, #0x10
  400c38:	540005a1 	b.ne	400cec <priv_ao_copy_inter2plan3+0xcc>
  400c3c:	eb03001f 	cmp	x0, x3
  400c40:	53017c27 	lsr	w7, w1, #1
  400c44:	540006c0 	b.eq	400d1c <priv_ao_copy_inter2plan3+0xfc>
  400c48:	8b214066 	add	x6, x3, w1, uxtw
  400c4c:	120004e7 	and	w7, w7, #0x3
  400c50:	53037c21 	lsr	w1, w1, #3
  400c54:	34000481 	cbz	w1, 400ce4 <priv_ao_copy_inter2plan3+0xc4>
  400c58:	d37c7024 	ubfiz	x4, x1, #4, #29
  400c5c:	2a0103e5 	mov	w5, w1
  400c60:	8b040004 	add	x4, x0, x4
  400c64:	aa0603e2 	mov	x2, x6
  400c68:	aa0303e1 	mov	x1, x3
  400c6c:	d503201f 	nop
  400c70:	0c408400 	ld2	{v0.4h, v1.4h}, [x0]
  400c74:	91004000 	add	x0, x0, #0x10
  400c78:	eb04001f 	cmp	x0, x4
  400c7c:	fc008420 	str	d0, [x1],#8
  400c80:	fc008441 	str	d1, [x2],#8
  400c84:	54ffff61 	b.ne	400c70 <priv_ao_copy_inter2plan3+0x50>
  400c88:	d37df0a1 	lsl	x1, x5, #3
  400c8c:	8b010063 	add	x3, x3, x1
  400c90:	8b0100c6 	add	x6, x6, x1
  400c94:	34000227 	cbz	w7, 400cd8 <priv_ao_copy_inter2plan3+0xb8>
  400c98:	79c00080 	ldrsh	w0, [x4]
  400c9c:	710004ff 	cmp	w7, #0x1
  400ca0:	79000060 	strh	w0, [x3]
  400ca4:	79c00480 	ldrsh	w0, [x4,#2]
  400ca8:	790000c0 	strh	w0, [x6]
  400cac:	54000160 	b.eq	400cd8 <priv_ao_copy_inter2plan3+0xb8>
  400cb0:	79c00880 	ldrsh	w0, [x4,#4]
  400cb4:	710008ff 	cmp	w7, #0x2
  400cb8:	79000460 	strh	w0, [x3,#2]
  400cbc:	79c00c80 	ldrsh	w0, [x4,#6]
  400cc0:	790004c0 	strh	w0, [x6,#2]
  400cc4:	540000a0 	b.eq	400cd8 <priv_ao_copy_inter2plan3+0xb8>
  400cc8:	79c01080 	ldrsh	w0, [x4,#8]
  400ccc:	79000860 	strh	w0, [x3,#4]
  400cd0:	79c01480 	ldrsh	w0, [x4,#10]
  400cd4:	790008c0 	strh	w0, [x6,#4]
  400cd8:	52800000 	mov	w0, #0x0                   	// #0
  400cdc:	a8c17bfd 	ldp	x29, x30, [sp],#16
  400ce0:	d65f03c0 	ret
  400ce4:	aa0003e4 	mov	x4, x0
  400ce8:	17ffffeb 	b	400c94 <priv_ao_copy_inter2plan3+0x74>
  400cec:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400cf0:	910de000 	add	x0, x0, #0x378
  400cf4:	97fffe5f 	bl	400670 <printf@plt>
  400cf8:	12800000 	mov	w0, #0xffffffff            	// #-1
  400cfc:	17fffff8 	b	400cdc <priv_ao_copy_inter2plan3+0xbc>
  400d00:	aa0003e1 	mov	x1, x0
  400d04:	aa0303e2 	mov	x2, x3
  400d08:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400d0c:	910a2000 	add	x0, x0, #0x288
  400d10:	97fffe58 	bl	400670 <printf@plt>
  400d14:	12800000 	mov	w0, #0xffffffff            	// #-1
  400d18:	17fffff1 	b	400cdc <priv_ao_copy_inter2plan3+0xbc>
  400d1c:	aa0003e2 	mov	x2, x0
  400d20:	b0000001 	adrp	x1, 401000 <banchMark2+0x90>
  400d24:	910c2020 	add	x0, x1, #0x308
  400d28:	aa0203e1 	mov	x1, x2
  400d2c:	97fffe51 	bl	400670 <printf@plt>
  400d30:	12800000 	mov	w0, #0xffffffff            	// #-1
  400d34:	17ffffea 	b	400cdc <priv_ao_copy_inter2plan3+0xbc>
  400d38:	d503201f 	nop
  400d3c:	d503201f 	nop

0000000000400d40 <banchMark>:
  400d40:	a9bc7bfd 	stp	x29, x30, [sp,#-64]!
  400d44:	d280a000 	mov	x0, #0x500                 	// #1280
  400d48:	910003fd 	mov	x29, sp
  400d4c:	a90153f3 	stp	x19, x20, [sp,#16]
  400d50:	a9025bf5 	stp	x21, x22, [sp,#32]
  400d54:	97fffe3b 	bl	400640 <malloc@plt>
  400d58:	aa0003f3 	mov	x19, x0
  400d5c:	d280a000 	mov	x0, #0x500                 	// #1280
  400d60:	97fffe38 	bl	400640 <malloc@plt>
  400d64:	d280a002 	mov	x2, #0x500                 	// #1280
  400d68:	aa0003f4 	mov	x20, x0
  400d6c:	52801561 	mov	w1, #0xab                  	// #171
  400d70:	97fffe2c 	bl	400620 <memset@plt>
  400d74:	aa1303e0 	mov	x0, x19
  400d78:	d280a002 	mov	x2, #0x500                 	// #1280
  400d7c:	52800001 	mov	w1, #0x0                   	// #0
  400d80:	97fffe28 	bl	400620 <memset@plt>
  400d84:	aa1303e3 	mov	x3, x19
  400d88:	aa1403e0 	mov	x0, x20
  400d8c:	52800202 	mov	w2, #0x10                  	// #16
  400d90:	52805001 	mov	w1, #0x280                 	// #640
  400d94:	b9003fff 	str	wzr, [sp,#60]
  400d98:	97fffe92 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400d9c:	d53be056 	mrs	x22, cntvct_el0
  400da0:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400da4:	d503201f 	nop
  400da8:	52805001 	mov	w1, #0x280                 	// #640
  400dac:	aa1303e3 	mov	x3, x19
  400db0:	aa1403e0 	mov	x0, x20
  400db4:	52800202 	mov	w2, #0x10                  	// #16
  400db8:	97fffe8a 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400dbc:	b9403fe1 	ldr	w1, [sp,#60]
  400dc0:	710006b5 	subs	w21, w21, #0x1
  400dc4:	39400260 	ldrb	w0, [x19]
  400dc8:	0b010000 	add	w0, w0, w1
  400dcc:	b9003fe0 	str	w0, [sp,#60]
  400dd0:	54fffec1 	b.ne	400da8 <banchMark+0x68>
  400dd4:	d53be041 	mrs	x1, cntvct_el0
  400dd8:	cb160021 	sub	x1, x1, x22
  400ddc:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400de0:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400de4:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400de8:	910ea000 	add	x0, x0, #0x3a8
  400dec:	d343fc21 	lsr	x1, x1, #3
  400df0:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400df4:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400df8:	9bc27c21 	umulh	x1, x1, x2
  400dfc:	d344fc21 	lsr	x1, x1, #4
  400e00:	97fffe1c 	bl	400670 <printf@plt>
  400e04:	d53be056 	mrs	x22, cntvct_el0
  400e08:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400e0c:	d503201f 	nop
  400e10:	52805001 	mov	w1, #0x280                 	// #640
  400e14:	aa1303e3 	mov	x3, x19
  400e18:	aa1403e0 	mov	x0, x20
  400e1c:	52800202 	mov	w2, #0x10                  	// #16
  400e20:	97fffeb4 	bl	4008f0 <priv_ao_copy_inter2plan1>
  400e24:	b9403fe1 	ldr	w1, [sp,#60]
  400e28:	710006b5 	subs	w21, w21, #0x1
  400e2c:	39400260 	ldrb	w0, [x19]
  400e30:	0b010000 	add	w0, w0, w1
  400e34:	b9003fe0 	str	w0, [sp,#60]
  400e38:	54fffec1 	b.ne	400e10 <banchMark+0xd0>
  400e3c:	d53be041 	mrs	x1, cntvct_el0
  400e40:	cb160021 	sub	x1, x1, x22
  400e44:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400e48:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400e4c:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400e50:	910f4000 	add	x0, x0, #0x3d0
  400e54:	d343fc21 	lsr	x1, x1, #3
  400e58:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400e5c:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400e60:	9bc27c21 	umulh	x1, x1, x2
  400e64:	d344fc21 	lsr	x1, x1, #4
  400e68:	97fffe02 	bl	400670 <printf@plt>
  400e6c:	d53be056 	mrs	x22, cntvct_el0
  400e70:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400e74:	d503201f 	nop
  400e78:	52805001 	mov	w1, #0x280                 	// #640
  400e7c:	aa1303e3 	mov	x3, x19
  400e80:	aa1403e0 	mov	x0, x20
  400e84:	52800202 	mov	w2, #0x10                  	// #16
  400e88:	97fffed6 	bl	4009e0 <priv_ao_copy_inter2plan2>
  400e8c:	b9403fe1 	ldr	w1, [sp,#60]
  400e90:	710006b5 	subs	w21, w21, #0x1
  400e94:	39400260 	ldrb	w0, [x19]
  400e98:	0b010000 	add	w0, w0, w1
  400e9c:	b9003fe0 	str	w0, [sp,#60]
  400ea0:	54fffec1 	b.ne	400e78 <banchMark+0x138>
  400ea4:	d53be041 	mrs	x1, cntvct_el0
  400ea8:	cb160021 	sub	x1, x1, x22
  400eac:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400eb0:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400eb4:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400eb8:	910fe000 	add	x0, x0, #0x3f8
  400ebc:	d343fc21 	lsr	x1, x1, #3
  400ec0:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400ec4:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400ec8:	9bc27c21 	umulh	x1, x1, x2
  400ecc:	d344fc21 	lsr	x1, x1, #4
  400ed0:	97fffde8 	bl	400670 <printf@plt>
  400ed4:	d53be056 	mrs	x22, cntvct_el0
  400ed8:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400edc:	d503201f 	nop
  400ee0:	52805001 	mov	w1, #0x280                 	// #640
  400ee4:	aa1303e3 	mov	x3, x19
  400ee8:	aa1403e0 	mov	x0, x20
  400eec:	52800202 	mov	w2, #0x10                  	// #16
  400ef0:	97ffff4c 	bl	400c20 <priv_ao_copy_inter2plan3>
  400ef4:	b9403fe1 	ldr	w1, [sp,#60]
  400ef8:	710006b5 	subs	w21, w21, #0x1
  400efc:	39400260 	ldrb	w0, [x19]
  400f00:	0b010000 	add	w0, w0, w1
  400f04:	b9003fe0 	str	w0, [sp,#60]
  400f08:	54fffec1 	b.ne	400ee0 <banchMark+0x1a0>
  400f0c:	d53be041 	mrs	x1, cntvct_el0
  400f10:	cb160021 	sub	x1, x1, x22
  400f14:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  400f18:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  400f1c:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400f20:	91108000 	add	x0, x0, #0x420
  400f24:	d343fc21 	lsr	x1, x1, #3
  400f28:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  400f2c:	f2e41882 	movk	x2, #0x20c4, lsl #48
  400f30:	9bc27c21 	umulh	x1, x1, x2
  400f34:	d344fc21 	lsr	x1, x1, #4
  400f38:	97fffdce 	bl	400670 <printf@plt>
  400f3c:	b9403fe1 	ldr	w1, [sp,#60]
  400f40:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400f44:	91112000 	add	x0, x0, #0x448
  400f48:	97fffdca 	bl	400670 <printf@plt>
  400f4c:	aa1303e0 	mov	x0, x19
  400f50:	97fffdb0 	bl	400610 <free@plt>
  400f54:	aa1403e0 	mov	x0, x20
  400f58:	a94153f3 	ldp	x19, x20, [sp,#16]
  400f5c:	a9425bf5 	ldp	x21, x22, [sp,#32]
  400f60:	a8c47bfd 	ldp	x29, x30, [sp],#64
  400f64:	17fffdab 	b	400610 <free@plt>
  400f68:	d503201f 	nop
  400f6c:	d503201f 	nop

0000000000400f70 <banchMark2>:
  400f70:	a9bb7bfd 	stp	x29, x30, [sp,#-80]!
  400f74:	d280a000 	mov	x0, #0x500                 	// #1280
  400f78:	910003fd 	mov	x29, sp
  400f7c:	a90153f3 	stp	x19, x20, [sp,#16]
  400f80:	a9025bf5 	stp	x21, x22, [sp,#32]
  400f84:	f9001bf7 	str	x23, [sp,#48]
  400f88:	fd001fe8 	str	d8, [sp,#56]
  400f8c:	97fffdad 	bl	400640 <malloc@plt>
  400f90:	aa0003f3 	mov	x19, x0
  400f94:	d280a000 	mov	x0, #0x500                 	// #1280
  400f98:	97fffdaa 	bl	400640 <malloc@plt>
  400f9c:	aa0003f4 	mov	x20, x0
  400fa0:	d280a002 	mov	x2, #0x500                 	// #1280
  400fa4:	52801561 	mov	w1, #0xab                  	// #171
  400fa8:	97fffd9e 	bl	400620 <memset@plt>
  400fac:	aa1303e0 	mov	x0, x19
  400fb0:	d280a002 	mov	x2, #0x500                 	// #1280
  400fb4:	52800001 	mov	w1, #0x0                   	// #0
  400fb8:	97fffd9a 	bl	400620 <memset@plt>
  400fbc:	b9004fff 	str	wzr, [sp,#76]
  400fc0:	d53be016 	mrs	x22, cntfrq_el0
  400fc4:	b0000000 	adrp	x0, 401000 <banchMark2+0x90>
  400fc8:	aa1603e1 	mov	x1, x22
  400fcc:	9111a000 	add	x0, x0, #0x468
  400fd0:	97fffda8 	bl	400670 <printf@plt>
  400fd4:	aa1303e3 	mov	x3, x19
  400fd8:	aa1403e0 	mov	x0, x20
  400fdc:	52800202 	mov	w2, #0x10                  	// #16
  400fe0:	52805001 	mov	w1, #0x280                 	// #640
  400fe4:	97fffdff 	bl	4007e0 <priv_ao_copy_inter2plan0>
  400fe8:	d53be057 	mrs	x23, cntvct_el0
  400fec:	52807d15 	mov	w21, #0x3e8                 	// #1000
  400ff0:	52805001 	mov	w1, #0x280                 	// #640
  400ff4:	aa1303e3 	mov	x3, x19
  400ff8:	aa1403e0 	mov	x0, x20
  400ffc:	52800202 	mov	w2, #0x10                  	// #16
  401000:	97fffdf8 	bl	4007e0 <priv_ao_copy_inter2plan0>
  401004:	b9404fe1 	ldr	w1, [sp,#76]
  401008:	710006b5 	subs	w21, w21, #0x1
  40100c:	39400260 	ldrb	w0, [x19]
  401010:	0b010000 	add	w0, w0, w1
  401014:	b9004fe0 	str	w0, [sp,#76]
  401018:	54fffec1 	b.ne	400ff0 <banchMark2+0x80>
  40101c:	d53be040 	mrs	x0, cntvct_el0
  401020:	cb170000 	sub	x0, x0, x23
  401024:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  401028:	f2e825c1 	movk	x1, #0x412e, lsl #48
  40102c:	9e670022 	fmov	d2, x1
  401030:	9e630000 	ucvtf	d0, x0
  401034:	9e6302c8 	ucvtf	d8, x22
  401038:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  40103c:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  401040:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  401044:	f2e811e1 	movk	x1, #0x408f, lsl #48
  401048:	9e670021 	fmov	d1, x1
  40104c:	d343fc01 	lsr	x1, x0, #3
  401050:	1e620800 	fmul	d0, d0, d2
  401054:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  401058:	f2e41882 	movk	x2, #0x20c4, lsl #48
  40105c:	90000000 	adrp	x0, 401000 <banchMark2+0x90>
  401060:	91124000 	add	x0, x0, #0x490
  401064:	9bc27c21 	umulh	x1, x1, x2
  401068:	1e681800 	fdiv	d0, d0, d8
  40106c:	d344fc21 	lsr	x1, x1, #4
  401070:	1e611800 	fdiv	d0, d0, d1
  401074:	97fffd7f 	bl	400670 <printf@plt>
  401078:	d53be056 	mrs	x22, cntvct_el0
  40107c:	52807d15 	mov	w21, #0x3e8                 	// #1000
  401080:	52805001 	mov	w1, #0x280                 	// #640
  401084:	aa1303e3 	mov	x3, x19
  401088:	aa1403e0 	mov	x0, x20
  40108c:	52800202 	mov	w2, #0x10                  	// #16
  401090:	97fffe18 	bl	4008f0 <priv_ao_copy_inter2plan1>
  401094:	b9404fe1 	ldr	w1, [sp,#76]
  401098:	710006b5 	subs	w21, w21, #0x1
  40109c:	39400260 	ldrb	w0, [x19]
  4010a0:	0b010000 	add	w0, w0, w1
  4010a4:	b9004fe0 	str	w0, [sp,#76]
  4010a8:	54fffec1 	b.ne	401080 <banchMark2+0x110>
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
  4010e8:	90000000 	adrp	x0, 401000 <banchMark2+0x90>
  4010ec:	91132000 	add	x0, x0, #0x4c8
  4010f0:	9bc27c21 	umulh	x1, x1, x2
  4010f4:	1e681800 	fdiv	d0, d0, d8
  4010f8:	d344fc21 	lsr	x1, x1, #4
  4010fc:	1e611800 	fdiv	d0, d0, d1
  401100:	97fffd5c 	bl	400670 <printf@plt>
  401104:	d53be056 	mrs	x22, cntvct_el0
  401108:	52807d15 	mov	w21, #0x3e8                 	// #1000
  40110c:	d503201f 	nop
  401110:	52805001 	mov	w1, #0x280                 	// #640
  401114:	aa1303e3 	mov	x3, x19
  401118:	aa1403e0 	mov	x0, x20
  40111c:	52800202 	mov	w2, #0x10                  	// #16
  401120:	97fffe30 	bl	4009e0 <priv_ao_copy_inter2plan2>
  401124:	b9404fe1 	ldr	w1, [sp,#76]
  401128:	710006b5 	subs	w21, w21, #0x1
  40112c:	39400260 	ldrb	w0, [x19]
  401130:	0b010000 	add	w0, w0, w1
  401134:	b9004fe0 	str	w0, [sp,#76]
  401138:	54fffec1 	b.ne	401110 <banchMark2+0x1a0>
  40113c:	d53be040 	mrs	x0, cntvct_el0
  401140:	cb160000 	sub	x0, x0, x22
  401144:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  401148:	f2e825c1 	movk	x1, #0x412e, lsl #48
  40114c:	9e670022 	fmov	d2, x1
  401150:	9e630000 	ucvtf	d0, x0
  401154:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  401158:	f2e811e1 	movk	x1, #0x408f, lsl #48
  40115c:	9e670021 	fmov	d1, x1
  401160:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  401164:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  401168:	d343fc01 	lsr	x1, x0, #3
  40116c:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  401170:	f2e41882 	movk	x2, #0x20c4, lsl #48
  401174:	1e620800 	fmul	d0, d0, d2
  401178:	90000000 	adrp	x0, 401000 <banchMark2+0x90>
  40117c:	91140000 	add	x0, x0, #0x500
  401180:	9bc27c21 	umulh	x1, x1, x2
  401184:	1e681800 	fdiv	d0, d0, d8
  401188:	d344fc21 	lsr	x1, x1, #4
  40118c:	1e611800 	fdiv	d0, d0, d1
  401190:	97fffd38 	bl	400670 <printf@plt>
  401194:	d53be056 	mrs	x22, cntvct_el0
  401198:	52807d15 	mov	w21, #0x3e8                 	// #1000
  40119c:	d503201f 	nop
  4011a0:	52805001 	mov	w1, #0x280                 	// #640
  4011a4:	aa1303e3 	mov	x3, x19
  4011a8:	aa1403e0 	mov	x0, x20
  4011ac:	52800202 	mov	w2, #0x10                  	// #16
  4011b0:	97fffe9c 	bl	400c20 <priv_ao_copy_inter2plan3>
  4011b4:	b9404fe1 	ldr	w1, [sp,#76]
  4011b8:	710006b5 	subs	w21, w21, #0x1
  4011bc:	39400260 	ldrb	w0, [x19]
  4011c0:	0b010000 	add	w0, w0, w1
  4011c4:	b9004fe0 	str	w0, [sp,#76]
  4011c8:	54fffec1 	b.ne	4011a0 <banchMark2+0x230>
  4011cc:	d53be040 	mrs	x0, cntvct_el0
  4011d0:	cb160000 	sub	x0, x0, x22
  4011d4:	d2d09001 	mov	x1, #0x848000000000        	// #145685290680320
  4011d8:	f2e825c1 	movk	x1, #0x412e, lsl #48
  4011dc:	9e670022 	fmov	d2, x1
  4011e0:	9e630000 	ucvtf	d0, x0
  4011e4:	d2c80001 	mov	x1, #0x400000000000        	// #70368744177664
  4011e8:	f2e811e1 	movk	x1, #0x408f, lsl #48
  4011ec:	9e670021 	fmov	d1, x1
  4011f0:	d29ef9e2 	mov	x2, #0xf7cf                	// #63439
  4011f4:	f2bc6a62 	movk	x2, #0xe353, lsl #16
  4011f8:	d343fc01 	lsr	x1, x0, #3
  4011fc:	f2d374a2 	movk	x2, #0x9ba5, lsl #32
  401200:	f2e41882 	movk	x2, #0x20c4, lsl #48
  401204:	1e620800 	fmul	d0, d0, d2
  401208:	90000000 	adrp	x0, 401000 <banchMark2+0x90>
  40120c:	9114e000 	add	x0, x0, #0x538
  401210:	9bc27c21 	umulh	x1, x1, x2
  401214:	1e681800 	fdiv	d0, d0, d8
  401218:	d344fc21 	lsr	x1, x1, #4
  40121c:	1e611800 	fdiv	d0, d0, d1
  401220:	97fffd14 	bl	400670 <printf@plt>
  401224:	b9404fe1 	ldr	w1, [sp,#76]
  401228:	90000000 	adrp	x0, 401000 <banchMark2+0x90>
  40122c:	91112000 	add	x0, x0, #0x448
  401230:	97fffd10 	bl	400670 <printf@plt>
  401234:	aa1303e0 	mov	x0, x19
  401238:	97fffcf6 	bl	400610 <free@plt>
  40123c:	aa1403e0 	mov	x0, x20
  401240:	fd401fe8 	ldr	d8, [sp,#56]
  401244:	a94153f3 	ldp	x19, x20, [sp,#16]
  401248:	a9425bf5 	ldp	x21, x22, [sp,#32]
  40124c:	f9401bf7 	ldr	x23, [sp,#48]
  401250:	a8c57bfd 	ldp	x29, x30, [sp],#80
  401254:	17fffcef 	b	400610 <free@plt>

Disassembly of section .fini:

0000000000401258 <_fini>:
  401258:	d503201f 	nop
  40125c:	a9bf7bfd 	stp	x29, x30, [sp,#-16]!
  401260:	910003fd 	mov	x29, sp
  401264:	a8c17bfd 	ldp	x29, x30, [sp],#16
  401268:	d65f03c0 	ret
