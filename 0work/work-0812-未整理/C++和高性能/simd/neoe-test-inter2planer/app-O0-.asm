
./app-O0-:     file format elf64-littleaarch64


Disassembly of section .init:

00000000004005c8 <_init>:
  4005c8:	d503201f 	nop
  4005cc:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  4005d0:	910003fd 	mov	x29, sp
  4005d4:	9400003b 	bl	4006c0 <call_weak_fn>
  4005d8:	a8c17bfd 	ldp	x29, x30, [sp], #16
  4005dc:	d65f03c0 	ret

Disassembly of section .plt:

00000000004005e0 <.plt>:
  4005e0:	a9bf7bf0 	stp	x16, x30, [sp, #-16]!
  4005e4:	b0000090 	adrp	x16, 411000 <__FRAME_END__+0xf438>
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

0000000000400680 <_start>:
  400680:	d503201f 	nop
  400684:	d280001d 	mov	x29, #0x0                   	// #0
  400688:	d280001e 	mov	x30, #0x0                   	// #0
  40068c:	aa0003e5 	mov	x5, x0
  400690:	f94003e1 	ldr	x1, [sp]
  400694:	910023e2 	add	x2, sp, #0x8
  400698:	910003e6 	mov	x6, sp
  40069c:	90000000 	adrp	x0, 400000 <__abi_tag-0x254>
  4006a0:	911ad000 	add	x0, x0, #0x6b4
  4006a4:	d2800003 	mov	x3, #0x0                   	// #0
  4006a8:	d2800004 	mov	x4, #0x0                   	// #0
  4006ac:	97ffffe1 	bl	400630 <__libc_start_main@plt>
  4006b0:	97ffffe8 	bl	400650 <abort@plt>

00000000004006b4 <__wrap_main>:
  4006b4:	d503201f 	nop
  4006b8:	140003e6 	b	401650 <main>

00000000004006bc <_dl_relocate_static_pie>:
  4006bc:	d65f03c0 	ret

00000000004006c0 <call_weak_fn>:
  4006c0:	b0000080 	adrp	x0, 411000 <__FRAME_END__+0xf438>
  4006c4:	f947f000 	ldr	x0, [x0, #4064]
  4006c8:	b4000040 	cbz	x0, 4006d0 <call_weak_fn+0x10>
  4006cc:	17ffffe5 	b	400660 <__gmon_start__@plt>
  4006d0:	d65f03c0 	ret

00000000004006d4 <deregister_tm_clones>:
  4006d4:	d0000080 	adrp	x0, 412000 <memcpy@GLIBC_2.17>
  4006d8:	91014001 	add	x1, x0, #0x50
  4006dc:	d0000080 	adrp	x0, 412000 <memcpy@GLIBC_2.17>
  4006e0:	91014000 	add	x0, x0, #0x50
  4006e4:	eb00003f 	cmp	x1, x0
  4006e8:	54000160 	b.eq	400714 <deregister_tm_clones+0x40>  // b.none
  4006ec:	d10043ff 	sub	sp, sp, #0x10
  4006f0:	b0000001 	adrp	x1, 401000 <banchMark+0xc8>
  4006f4:	f9434421 	ldr	x1, [x1, #1672]
  4006f8:	f90007e1 	str	x1, [sp, #8]
  4006fc:	b4000081 	cbz	x1, 40070c <deregister_tm_clones+0x38>
  400700:	aa0103f0 	mov	x16, x1
  400704:	910043ff 	add	sp, sp, #0x10
  400708:	d61f0200 	br	x16
  40070c:	910043ff 	add	sp, sp, #0x10
  400710:	d65f03c0 	ret
  400714:	d65f03c0 	ret

0000000000400718 <register_tm_clones>:
  400718:	d0000080 	adrp	x0, 412000 <memcpy@GLIBC_2.17>
  40071c:	91014001 	add	x1, x0, #0x50
  400720:	d0000080 	adrp	x0, 412000 <memcpy@GLIBC_2.17>
  400724:	91014000 	add	x0, x0, #0x50
  400728:	cb000021 	sub	x1, x1, x0
  40072c:	d2800042 	mov	x2, #0x2                   	// #2
  400730:	9343fc21 	asr	x1, x1, #3
  400734:	9ac20c21 	sdiv	x1, x1, x2
  400738:	b4000161 	cbz	x1, 400764 <register_tm_clones+0x4c>
  40073c:	d10043ff 	sub	sp, sp, #0x10
  400740:	b0000002 	adrp	x2, 401000 <banchMark+0xc8>
  400744:	f9434842 	ldr	x2, [x2, #1680]
  400748:	f90007e2 	str	x2, [sp, #8]
  40074c:	b4000082 	cbz	x2, 40075c <register_tm_clones+0x44>
  400750:	aa0203f0 	mov	x16, x2
  400754:	910043ff 	add	sp, sp, #0x10
  400758:	d61f0200 	br	x16
  40075c:	910043ff 	add	sp, sp, #0x10
  400760:	d65f03c0 	ret
  400764:	d65f03c0 	ret

0000000000400768 <__do_global_dtors_aux>:
  400768:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
  40076c:	910003fd 	mov	x29, sp
  400770:	f9000bf3 	str	x19, [sp, #16]
  400774:	d0000093 	adrp	x19, 412000 <memcpy@GLIBC_2.17>
  400778:	39414260 	ldrb	w0, [x19, #80]
  40077c:	35000080 	cbnz	w0, 40078c <__do_global_dtors_aux+0x24>
  400780:	97ffffd5 	bl	4006d4 <deregister_tm_clones>
  400784:	52800020 	mov	w0, #0x1                   	// #1
  400788:	39014260 	strb	w0, [x19, #80]
  40078c:	f9400bf3 	ldr	x19, [sp, #16]
  400790:	a8c27bfd 	ldp	x29, x30, [sp], #32
  400794:	d65f03c0 	ret

0000000000400798 <frame_dummy>:
  400798:	17ffffe0 	b	400718 <register_tm_clones>

000000000040079c <priv_ao_copy_inter2plan0>:
  40079c:	a9bc7bfd 	stp	x29, x30, [sp, #-64]!
  4007a0:	910003fd 	mov	x29, sp
  4007a4:	f90017e0 	str	x0, [sp, #40]
  4007a8:	b90027e1 	str	w1, [sp, #36]
  4007ac:	b90023e2 	str	w2, [sp, #32]
  4007b0:	f9000fe3 	str	x3, [sp, #24]
  4007b4:	f94017e0 	ldr	x0, [sp, #40]
  4007b8:	f100001f 	cmp	x0, #0x0
  4007bc:	54000080 	b.eq	4007cc <priv_ao_copy_inter2plan0+0x30>  // b.none
  4007c0:	f9400fe0 	ldr	x0, [sp, #24]
  4007c4:	f100001f 	cmp	x0, #0x0
  4007c8:	54000101 	b.ne	4007e8 <priv_ao_copy_inter2plan0+0x4c>  // b.any
  4007cc:	f9400fe2 	ldr	x2, [sp, #24]
  4007d0:	f94017e1 	ldr	x1, [sp, #40]
  4007d4:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  4007d8:	911a6000 	add	x0, x0, #0x698
  4007dc:	97ffffa5 	bl	400670 <printf@plt>
  4007e0:	12800000 	mov	w0, #0xffffffff            	// #-1
  4007e4:	14000049 	b	400908 <priv_ao_copy_inter2plan0+0x16c>
  4007e8:	b9003fff 	str	wzr, [sp, #60]
  4007ec:	b94023e0 	ldr	w0, [sp, #32]
  4007f0:	53037c00 	lsr	w0, w0, #3
  4007f4:	b9003be0 	str	w0, [sp, #56]
  4007f8:	b94027e1 	ldr	w1, [sp, #36]
  4007fc:	b9403be0 	ldr	w0, [sp, #56]
  400800:	1ac00820 	udiv	w0, w1, w0
  400804:	b90037e0 	str	w0, [sp, #52]
  400808:	b94037e1 	ldr	w1, [sp, #52]
  40080c:	b9403be0 	ldr	w0, [sp, #56]
  400810:	1b007c20 	mul	w0, w1, w0
  400814:	b94027e1 	ldr	w1, [sp, #36]
  400818:	6b00003f 	cmp	w1, w0
  40081c:	540000e9 	b.ls	400838 <priv_ao_copy_inter2plan0+0x9c>  // b.plast
  400820:	b9403be3 	ldr	w3, [sp, #56]
  400824:	b94037e2 	ldr	w2, [sp, #52]
  400828:	b94027e1 	ldr	w1, [sp, #36]
  40082c:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  400830:	911b2000 	add	x0, x0, #0x6c8
  400834:	97ffff8f 	bl	400670 <printf@plt>
  400838:	f94017e1 	ldr	x1, [sp, #40]
  40083c:	f9400fe0 	ldr	x0, [sp, #24]
  400840:	eb00003f 	cmp	x1, x0
  400844:	54000101 	b.ne	400864 <priv_ao_copy_inter2plan0+0xc8>  // b.any
  400848:	f9400fe2 	ldr	x2, [sp, #24]
  40084c:	f94017e1 	ldr	x1, [sp, #40]
  400850:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  400854:	911c6000 	add	x0, x0, #0x718
  400858:	97ffff86 	bl	400670 <printf@plt>
  40085c:	12800000 	mov	w0, #0xffffffff            	// #-1
  400860:	1400002a 	b	400908 <priv_ao_copy_inter2plan0+0x16c>
  400864:	b9003fff 	str	wzr, [sp, #60]
  400868:	14000023 	b	4008f4 <priv_ao_copy_inter2plan0+0x158>
  40086c:	b9403fe0 	ldr	w0, [sp, #60]
  400870:	f9400fe1 	ldr	x1, [sp, #24]
  400874:	8b000023 	add	x3, x1, x0
  400878:	b9403fe0 	ldr	w0, [sp, #60]
  40087c:	0b000000 	add	w0, w0, w0
  400880:	2a0003e0 	mov	w0, w0
  400884:	f94017e1 	ldr	x1, [sp, #40]
  400888:	8b000020 	add	x0, x1, x0
  40088c:	b9403be1 	ldr	w1, [sp, #56]
  400890:	aa0103e2 	mov	x2, x1
  400894:	aa0003e1 	mov	x1, x0
  400898:	aa0303e0 	mov	x0, x3
  40089c:	97ffff59 	bl	400600 <memcpy@plt>
  4008a0:	b94027e1 	ldr	w1, [sp, #36]
  4008a4:	b9403fe0 	ldr	w0, [sp, #60]
  4008a8:	8b000020 	add	x0, x1, x0
  4008ac:	f9400fe1 	ldr	x1, [sp, #24]
  4008b0:	8b000023 	add	x3, x1, x0
  4008b4:	b9403fe0 	ldr	w0, [sp, #60]
  4008b8:	0b000000 	add	w0, w0, w0
  4008bc:	2a0003e1 	mov	w1, w0
  4008c0:	b9403be0 	ldr	w0, [sp, #56]
  4008c4:	8b000020 	add	x0, x1, x0
  4008c8:	f94017e1 	ldr	x1, [sp, #40]
  4008cc:	8b000020 	add	x0, x1, x0
  4008d0:	b9403be1 	ldr	w1, [sp, #56]
  4008d4:	aa0103e2 	mov	x2, x1
  4008d8:	aa0003e1 	mov	x1, x0
  4008dc:	aa0303e0 	mov	x0, x3
  4008e0:	97ffff48 	bl	400600 <memcpy@plt>
  4008e4:	b9403fe1 	ldr	w1, [sp, #60]
  4008e8:	b9403be0 	ldr	w0, [sp, #56]
  4008ec:	0b000020 	add	w0, w1, w0
  4008f0:	b9003fe0 	str	w0, [sp, #60]
  4008f4:	b9403fe1 	ldr	w1, [sp, #60]
  4008f8:	b94027e0 	ldr	w0, [sp, #36]
  4008fc:	6b00003f 	cmp	w1, w0
  400900:	54fffb63 	b.cc	40086c <priv_ao_copy_inter2plan0+0xd0>  // b.lo, b.ul, b.last
  400904:	52800000 	mov	w0, #0x0                   	// #0
  400908:	a8c47bfd 	ldp	x29, x30, [sp], #64
  40090c:	d65f03c0 	ret

0000000000400910 <priv_ao_copy_inter2plan1>:
  400910:	a9bb7bfd 	stp	x29, x30, [sp, #-80]!
  400914:	910003fd 	mov	x29, sp
  400918:	f90017e0 	str	x0, [sp, #40]
  40091c:	b90027e1 	str	w1, [sp, #36]
  400920:	b90023e2 	str	w2, [sp, #32]
  400924:	f9000fe3 	str	x3, [sp, #24]
  400928:	f94017e0 	ldr	x0, [sp, #40]
  40092c:	f100001f 	cmp	x0, #0x0
  400930:	54000080 	b.eq	400940 <priv_ao_copy_inter2plan1+0x30>  // b.none
  400934:	f9400fe0 	ldr	x0, [sp, #24]
  400938:	f100001f 	cmp	x0, #0x0
  40093c:	54000101 	b.ne	40095c <priv_ao_copy_inter2plan1+0x4c>  // b.any
  400940:	f9400fe2 	ldr	x2, [sp, #24]
  400944:	f94017e1 	ldr	x1, [sp, #40]
  400948:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  40094c:	911a6000 	add	x0, x0, #0x698
  400950:	97ffff48 	bl	400670 <printf@plt>
  400954:	12800000 	mov	w0, #0xffffffff            	// #-1
  400958:	1400004e 	b	400a90 <priv_ao_copy_inter2plan1+0x180>
  40095c:	b9004fff 	str	wzr, [sp, #76]
  400960:	b94023e0 	ldr	w0, [sp, #32]
  400964:	53037c00 	lsr	w0, w0, #3
  400968:	b9004be0 	str	w0, [sp, #72]
  40096c:	b94027e1 	ldr	w1, [sp, #36]
  400970:	b9404be0 	ldr	w0, [sp, #72]
  400974:	1ac00820 	udiv	w0, w1, w0
  400978:	b90047e0 	str	w0, [sp, #68]
  40097c:	b94047e1 	ldr	w1, [sp, #68]
  400980:	b9404be0 	ldr	w0, [sp, #72]
  400984:	1b007c20 	mul	w0, w1, w0
  400988:	b94027e1 	ldr	w1, [sp, #36]
  40098c:	6b00003f 	cmp	w1, w0
  400990:	540000e9 	b.ls	4009ac <priv_ao_copy_inter2plan1+0x9c>  // b.plast
  400994:	b9404be3 	ldr	w3, [sp, #72]
  400998:	b94047e2 	ldr	w2, [sp, #68]
  40099c:	b94027e1 	ldr	w1, [sp, #36]
  4009a0:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  4009a4:	911b2000 	add	x0, x0, #0x6c8
  4009a8:	97ffff32 	bl	400670 <printf@plt>
  4009ac:	f94017e1 	ldr	x1, [sp, #40]
  4009b0:	f9400fe0 	ldr	x0, [sp, #24]
  4009b4:	eb00003f 	cmp	x1, x0
  4009b8:	54000101 	b.ne	4009d8 <priv_ao_copy_inter2plan1+0xc8>  // b.any
  4009bc:	f9400fe2 	ldr	x2, [sp, #24]
  4009c0:	f94017e1 	ldr	x1, [sp, #40]
  4009c4:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  4009c8:	911c6000 	add	x0, x0, #0x718
  4009cc:	97ffff29 	bl	400670 <printf@plt>
  4009d0:	12800000 	mov	w0, #0xffffffff            	// #-1
  4009d4:	1400002f 	b	400a90 <priv_ao_copy_inter2plan1+0x180>
  4009d8:	f94017e0 	ldr	x0, [sp, #40]
  4009dc:	f9001fe0 	str	x0, [sp, #56]
  4009e0:	f9400fe0 	ldr	x0, [sp, #24]
  4009e4:	f9001be0 	str	x0, [sp, #48]
  4009e8:	b9004fff 	str	wzr, [sp, #76]
  4009ec:	14000024 	b	400a7c <priv_ao_copy_inter2plan1+0x16c>
  4009f0:	b9404fe0 	ldr	w0, [sp, #76]
  4009f4:	0b000000 	add	w0, w0, w0
  4009f8:	2a0003e0 	mov	w0, w0
  4009fc:	8b000000 	add	x0, x0, x0
  400a00:	aa0003e1 	mov	x1, x0
  400a04:	f9401fe0 	ldr	x0, [sp, #56]
  400a08:	8b010001 	add	x1, x0, x1
  400a0c:	b9404fe0 	ldr	w0, [sp, #76]
  400a10:	8b000000 	add	x0, x0, x0
  400a14:	aa0003e2 	mov	x2, x0
  400a18:	f9401be0 	ldr	x0, [sp, #48]
  400a1c:	8b020000 	add	x0, x0, x2
  400a20:	79c00021 	ldrsh	w1, [x1]
  400a24:	79000001 	strh	w1, [x0]
  400a28:	b9404fe0 	ldr	w0, [sp, #76]
  400a2c:	0b000000 	add	w0, w0, w0
  400a30:	11000400 	add	w0, w0, #0x1
  400a34:	2a0003e0 	mov	w0, w0
  400a38:	8b000000 	add	x0, x0, x0
  400a3c:	aa0003e1 	mov	x1, x0
  400a40:	f9401fe0 	ldr	x0, [sp, #56]
  400a44:	8b010001 	add	x1, x0, x1
  400a48:	b94047e2 	ldr	w2, [sp, #68]
  400a4c:	b9404fe0 	ldr	w0, [sp, #76]
  400a50:	0b000040 	add	w0, w2, w0
  400a54:	2a0003e0 	mov	w0, w0
  400a58:	8b000000 	add	x0, x0, x0
  400a5c:	aa0003e2 	mov	x2, x0
  400a60:	f9401be0 	ldr	x0, [sp, #48]
  400a64:	8b020000 	add	x0, x0, x2
  400a68:	79c00021 	ldrsh	w1, [x1]
  400a6c:	79000001 	strh	w1, [x0]
  400a70:	b9404fe0 	ldr	w0, [sp, #76]
  400a74:	11000400 	add	w0, w0, #0x1
  400a78:	b9004fe0 	str	w0, [sp, #76]
  400a7c:	b9404fe1 	ldr	w1, [sp, #76]
  400a80:	b94047e0 	ldr	w0, [sp, #68]
  400a84:	6b00003f 	cmp	w1, w0
  400a88:	54fffb43 	b.cc	4009f0 <priv_ao_copy_inter2plan1+0xe0>  // b.lo, b.ul, b.last
  400a8c:	52800000 	mov	w0, #0x0                   	// #0
  400a90:	a8c57bfd 	ldp	x29, x30, [sp], #80
  400a94:	d65f03c0 	ret

0000000000400a98 <priv_ao_copy_inter2plan2>:
  400a98:	a9ba7bfd 	stp	x29, x30, [sp, #-96]!
  400a9c:	910003fd 	mov	x29, sp
  400aa0:	f90017e0 	str	x0, [sp, #40]
  400aa4:	b90027e1 	str	w1, [sp, #36]
  400aa8:	b90023e2 	str	w2, [sp, #32]
  400aac:	f9000fe3 	str	x3, [sp, #24]
  400ab0:	f94017e0 	ldr	x0, [sp, #40]
  400ab4:	f100001f 	cmp	x0, #0x0
  400ab8:	54000080 	b.eq	400ac8 <priv_ao_copy_inter2plan2+0x30>  // b.none
  400abc:	f9400fe0 	ldr	x0, [sp, #24]
  400ac0:	f100001f 	cmp	x0, #0x0
  400ac4:	54000101 	b.ne	400ae4 <priv_ao_copy_inter2plan2+0x4c>  // b.any
  400ac8:	f9400fe2 	ldr	x2, [sp, #24]
  400acc:	f94017e1 	ldr	x1, [sp, #40]
  400ad0:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  400ad4:	911a6000 	add	x0, x0, #0x698
  400ad8:	97fffee6 	bl	400670 <printf@plt>
  400adc:	12800000 	mov	w0, #0xffffffff            	// #-1
  400ae0:	14000086 	b	400cf8 <priv_ao_copy_inter2plan2+0x260>
  400ae4:	b94023e0 	ldr	w0, [sp, #32]
  400ae8:	7100401f 	cmp	w0, #0x10
  400aec:	540000c0 	b.eq	400b04 <priv_ao_copy_inter2plan2+0x6c>  // b.none
  400af0:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  400af4:	911d6000 	add	x0, x0, #0x758
  400af8:	97fffede 	bl	400670 <printf@plt>
  400afc:	12800000 	mov	w0, #0xffffffff            	// #-1
  400b00:	1400007e 	b	400cf8 <priv_ao_copy_inter2plan2+0x260>
  400b04:	b94023e0 	ldr	w0, [sp, #32]
  400b08:	53037c00 	lsr	w0, w0, #3
  400b0c:	b9003fe0 	str	w0, [sp, #60]
  400b10:	b94027e1 	ldr	w1, [sp, #36]
  400b14:	b9403fe0 	ldr	w0, [sp, #60]
  400b18:	1ac00820 	udiv	w0, w1, w0
  400b1c:	b9003be0 	str	w0, [sp, #56]
  400b20:	f94017e1 	ldr	x1, [sp, #40]
  400b24:	f9400fe0 	ldr	x0, [sp, #24]
  400b28:	eb00003f 	cmp	x1, x0
  400b2c:	54000101 	b.ne	400b4c <priv_ao_copy_inter2plan2+0xb4>  // b.any
  400b30:	f9400fe2 	ldr	x2, [sp, #24]
  400b34:	f94017e1 	ldr	x1, [sp, #40]
  400b38:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  400b3c:	911c6000 	add	x0, x0, #0x718
  400b40:	97fffecc 	bl	400670 <printf@plt>
  400b44:	12800000 	mov	w0, #0xffffffff            	// #-1
  400b48:	1400006c 	b	400cf8 <priv_ao_copy_inter2plan2+0x260>
  400b4c:	f94017e0 	ldr	x0, [sp, #40]
  400b50:	f9002fe0 	str	x0, [sp, #88]
  400b54:	f9400fe0 	ldr	x0, [sp, #24]
  400b58:	f9002be0 	str	x0, [sp, #80]
  400b5c:	b94027e0 	ldr	w0, [sp, #36]
  400b60:	f9400fe1 	ldr	x1, [sp, #24]
  400b64:	8b000020 	add	x0, x1, x0
  400b68:	f90027e0 	str	x0, [sp, #72]
  400b6c:	b9403be0 	ldr	w0, [sp, #56]
  400b70:	53027c00 	lsr	w0, w0, #2
  400b74:	b90047e0 	str	w0, [sp, #68]
  400b78:	b9403be0 	ldr	w0, [sp, #56]
  400b7c:	12000400 	and	w0, w0, #0x3
  400b80:	b90043e0 	str	w0, [sp, #64]
  400b84:	14000041 	b	400c88 <priv_ao_copy_inter2plan2+0x1f0>
  400b88:	f9402fe1 	ldr	x1, [sp, #88]
  400b8c:	91000820 	add	x0, x1, #0x2
  400b90:	f9002fe0 	str	x0, [sp, #88]
  400b94:	f9402be0 	ldr	x0, [sp, #80]
  400b98:	91000802 	add	x2, x0, #0x2
  400b9c:	f9002be2 	str	x2, [sp, #80]
  400ba0:	79c00021 	ldrsh	w1, [x1]
  400ba4:	79000001 	strh	w1, [x0]
  400ba8:	f9402fe1 	ldr	x1, [sp, #88]
  400bac:	91000820 	add	x0, x1, #0x2
  400bb0:	f9002fe0 	str	x0, [sp, #88]
  400bb4:	f94027e0 	ldr	x0, [sp, #72]
  400bb8:	91000802 	add	x2, x0, #0x2
  400bbc:	f90027e2 	str	x2, [sp, #72]
  400bc0:	79c00021 	ldrsh	w1, [x1]
  400bc4:	79000001 	strh	w1, [x0]
  400bc8:	f9402fe1 	ldr	x1, [sp, #88]
  400bcc:	91000820 	add	x0, x1, #0x2
  400bd0:	f9002fe0 	str	x0, [sp, #88]
  400bd4:	f9402be0 	ldr	x0, [sp, #80]
  400bd8:	91000802 	add	x2, x0, #0x2
  400bdc:	f9002be2 	str	x2, [sp, #80]
  400be0:	79c00021 	ldrsh	w1, [x1]
  400be4:	79000001 	strh	w1, [x0]
  400be8:	f9402fe1 	ldr	x1, [sp, #88]
  400bec:	91000820 	add	x0, x1, #0x2
  400bf0:	f9002fe0 	str	x0, [sp, #88]
  400bf4:	f94027e0 	ldr	x0, [sp, #72]
  400bf8:	91000802 	add	x2, x0, #0x2
  400bfc:	f90027e2 	str	x2, [sp, #72]
  400c00:	79c00021 	ldrsh	w1, [x1]
  400c04:	79000001 	strh	w1, [x0]
  400c08:	f9402fe1 	ldr	x1, [sp, #88]
  400c0c:	91000820 	add	x0, x1, #0x2
  400c10:	f9002fe0 	str	x0, [sp, #88]
  400c14:	f9402be0 	ldr	x0, [sp, #80]
  400c18:	91000802 	add	x2, x0, #0x2
  400c1c:	f9002be2 	str	x2, [sp, #80]
  400c20:	79c00021 	ldrsh	w1, [x1]
  400c24:	79000001 	strh	w1, [x0]
  400c28:	f9402fe1 	ldr	x1, [sp, #88]
  400c2c:	91000820 	add	x0, x1, #0x2
  400c30:	f9002fe0 	str	x0, [sp, #88]
  400c34:	f94027e0 	ldr	x0, [sp, #72]
  400c38:	91000802 	add	x2, x0, #0x2
  400c3c:	f90027e2 	str	x2, [sp, #72]
  400c40:	79c00021 	ldrsh	w1, [x1]
  400c44:	79000001 	strh	w1, [x0]
  400c48:	f9402fe1 	ldr	x1, [sp, #88]
  400c4c:	91000820 	add	x0, x1, #0x2
  400c50:	f9002fe0 	str	x0, [sp, #88]
  400c54:	f9402be0 	ldr	x0, [sp, #80]
  400c58:	91000802 	add	x2, x0, #0x2
  400c5c:	f9002be2 	str	x2, [sp, #80]
  400c60:	79c00021 	ldrsh	w1, [x1]
  400c64:	79000001 	strh	w1, [x0]
  400c68:	f9402fe1 	ldr	x1, [sp, #88]
  400c6c:	91000820 	add	x0, x1, #0x2
  400c70:	f9002fe0 	str	x0, [sp, #88]
  400c74:	f94027e0 	ldr	x0, [sp, #72]
  400c78:	91000802 	add	x2, x0, #0x2
  400c7c:	f90027e2 	str	x2, [sp, #72]
  400c80:	79c00021 	ldrsh	w1, [x1]
  400c84:	79000001 	strh	w1, [x0]
  400c88:	b94047e0 	ldr	w0, [sp, #68]
  400c8c:	51000401 	sub	w1, w0, #0x1
  400c90:	b90047e1 	str	w1, [sp, #68]
  400c94:	7100001f 	cmp	w0, #0x0
  400c98:	54fff781 	b.ne	400b88 <priv_ao_copy_inter2plan2+0xf0>  // b.any
  400c9c:	14000011 	b	400ce0 <priv_ao_copy_inter2plan2+0x248>
  400ca0:	f9402fe1 	ldr	x1, [sp, #88]
  400ca4:	91000820 	add	x0, x1, #0x2
  400ca8:	f9002fe0 	str	x0, [sp, #88]
  400cac:	f9402be0 	ldr	x0, [sp, #80]
  400cb0:	91000802 	add	x2, x0, #0x2
  400cb4:	f9002be2 	str	x2, [sp, #80]
  400cb8:	79c00021 	ldrsh	w1, [x1]
  400cbc:	79000001 	strh	w1, [x0]
  400cc0:	f9402fe1 	ldr	x1, [sp, #88]
  400cc4:	91000820 	add	x0, x1, #0x2
  400cc8:	f9002fe0 	str	x0, [sp, #88]
  400ccc:	f94027e0 	ldr	x0, [sp, #72]
  400cd0:	91000802 	add	x2, x0, #0x2
  400cd4:	f90027e2 	str	x2, [sp, #72]
  400cd8:	79c00021 	ldrsh	w1, [x1]
  400cdc:	79000001 	strh	w1, [x0]
  400ce0:	b94043e0 	ldr	w0, [sp, #64]
  400ce4:	51000401 	sub	w1, w0, #0x1
  400ce8:	b90043e1 	str	w1, [sp, #64]
  400cec:	7100001f 	cmp	w0, #0x0
  400cf0:	54fffd81 	b.ne	400ca0 <priv_ao_copy_inter2plan2+0x208>  // b.any
  400cf4:	52800000 	mov	w0, #0x0                   	// #0
  400cf8:	a8c67bfd 	ldp	x29, x30, [sp], #96
  400cfc:	d65f03c0 	ret

0000000000400d00 <priv_ao_copy_inter2plan3>:
  400d00:	a9b47bfd 	stp	x29, x30, [sp, #-192]!
  400d04:	910003fd 	mov	x29, sp
  400d08:	f90017e0 	str	x0, [sp, #40]
  400d0c:	b90027e1 	str	w1, [sp, #36]
  400d10:	b90023e2 	str	w2, [sp, #32]
  400d14:	f9000fe3 	str	x3, [sp, #24]
  400d18:	f94017e0 	ldr	x0, [sp, #40]
  400d1c:	f100001f 	cmp	x0, #0x0
  400d20:	54000080 	b.eq	400d30 <priv_ao_copy_inter2plan3+0x30>  // b.none
  400d24:	f9400fe0 	ldr	x0, [sp, #24]
  400d28:	f100001f 	cmp	x0, #0x0
  400d2c:	54000101 	b.ne	400d4c <priv_ao_copy_inter2plan3+0x4c>  // b.any
  400d30:	f9400fe2 	ldr	x2, [sp, #24]
  400d34:	f94017e1 	ldr	x1, [sp, #40]
  400d38:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  400d3c:	911a6000 	add	x0, x0, #0x698
  400d40:	97fffe4c 	bl	400670 <printf@plt>
  400d44:	12800000 	mov	w0, #0xffffffff            	// #-1
  400d48:	1400006e 	b	400f00 <priv_ao_copy_inter2plan3+0x200>
  400d4c:	b94023e0 	ldr	w0, [sp, #32]
  400d50:	7100401f 	cmp	w0, #0x10
  400d54:	540000c0 	b.eq	400d6c <priv_ao_copy_inter2plan3+0x6c>  // b.none
  400d58:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  400d5c:	911e2000 	add	x0, x0, #0x788
  400d60:	97fffe44 	bl	400670 <printf@plt>
  400d64:	12800000 	mov	w0, #0xffffffff            	// #-1
  400d68:	14000066 	b	400f00 <priv_ao_copy_inter2plan3+0x200>
  400d6c:	b94023e0 	ldr	w0, [sp, #32]
  400d70:	53037c00 	lsr	w0, w0, #3
  400d74:	b9009fe0 	str	w0, [sp, #156]
  400d78:	b94027e1 	ldr	w1, [sp, #36]
  400d7c:	b9409fe0 	ldr	w0, [sp, #156]
  400d80:	1ac00820 	udiv	w0, w1, w0
  400d84:	b9009be0 	str	w0, [sp, #152]
  400d88:	f94017e1 	ldr	x1, [sp, #40]
  400d8c:	f9400fe0 	ldr	x0, [sp, #24]
  400d90:	eb00003f 	cmp	x1, x0
  400d94:	54000101 	b.ne	400db4 <priv_ao_copy_inter2plan3+0xb4>  // b.any
  400d98:	f9400fe2 	ldr	x2, [sp, #24]
  400d9c:	f94017e1 	ldr	x1, [sp, #40]
  400da0:	b0000000 	adrp	x0, 401000 <banchMark+0xc8>
  400da4:	911c6000 	add	x0, x0, #0x718
  400da8:	97fffe32 	bl	400670 <printf@plt>
  400dac:	12800000 	mov	w0, #0xffffffff            	// #-1
  400db0:	14000054 	b	400f00 <priv_ao_copy_inter2plan3+0x200>
  400db4:	f94017e0 	ldr	x0, [sp, #40]
  400db8:	f9005fe0 	str	x0, [sp, #184]
  400dbc:	f9400fe0 	ldr	x0, [sp, #24]
  400dc0:	f9005be0 	str	x0, [sp, #176]
  400dc4:	b94027e0 	ldr	w0, [sp, #36]
  400dc8:	f9400fe1 	ldr	x1, [sp, #24]
  400dcc:	8b000020 	add	x0, x1, x0
  400dd0:	f90057e0 	str	x0, [sp, #168]
  400dd4:	b9409be0 	ldr	w0, [sp, #152]
  400dd8:	53027c00 	lsr	w0, w0, #2
  400ddc:	b900a7e0 	str	w0, [sp, #164]
  400de0:	b9409be0 	ldr	w0, [sp, #152]
  400de4:	12000400 	and	w0, w0, #0x3
  400de8:	b900a3e0 	str	w0, [sp, #160]
  400dec:	14000029 	b	400e90 <priv_ao_copy_inter2plan3+0x190>
  400df0:	f9405fe0 	ldr	x0, [sp, #184]
  400df4:	f9003be0 	str	x0, [sp, #112]
__attribute__ ((__always_inline__, __gnu_inline__, __artificial__))
vld2_s16 (const int16_t * __a)
{
  int16x4x2_t ret;
  __builtin_aarch64_simd_oi __o;
  __o = __builtin_aarch64_ld2v4hi ((const __builtin_aarch64_simd_hi *) __a);
  400df8:	910143e0 	add	x0, sp, #0x50
  400dfc:	f9403be1 	ldr	x1, [sp, #112]
  400e00:	0c408420 	ld2	{v0.4h, v1.4h}, [x1]
  400e04:	4c00a000 	st1	{v0.16b, v1.16b}, [x0]
  ret.val[0] = (int16x4_t) __builtin_aarch64_get_dregoiv4hi (__o, 0);
  400e08:	910143e0 	add	x0, sp, #0x50
  400e0c:	4c40a000 	ld1	{v0.16b, v1.16b}, [x0]
  400e10:	fd001be0 	str	d0, [sp, #48]
  ret.val[1] = (int16x4_t) __builtin_aarch64_get_dregoiv4hi (__o, 1);
  400e14:	910143e0 	add	x0, sp, #0x50
  400e18:	4c40a000 	ld1	{v0.16b, v1.16b}, [x0]
  400e1c:	4ea11c20 	mov	v0.16b, v1.16b
  400e20:	fd001fe0 	str	d0, [sp, #56]
  return ret;
  400e24:	a94307e0 	ldp	x0, x1, [sp, #48]
  400e28:	a90407e0 	stp	x0, x1, [sp, #64]
  400e2c:	fd4023e0 	ldr	d0, [sp, #64]
  400e30:	f9405be0 	ldr	x0, [sp, #176]
  400e34:	f90043e0 	str	x0, [sp, #128]
  400e38:	fd003fe0 	str	d0, [sp, #120]

__extension__ extern __inline void
__attribute__ ((__always_inline__, __gnu_inline__, __artificial__))
vst1_s16 (int16_t *__a, int16x4_t __b)
{
  __builtin_aarch64_st1v4hi ((__builtin_aarch64_simd_hi *) __a, __b);
  400e3c:	f94043e0 	ldr	x0, [sp, #128]
  400e40:	fd403fe0 	ldr	d0, [sp, #120]
  400e44:	fd000000 	str	d0, [x0]
}
  400e48:	d503201f 	nop
  400e4c:	fd4027e0 	ldr	d0, [sp, #72]
  400e50:	f94057e0 	ldr	x0, [sp, #168]
  400e54:	f9004be0 	str	x0, [sp, #144]
  400e58:	fd0047e0 	str	d0, [sp, #136]
  __builtin_aarch64_st1v4hi ((__builtin_aarch64_simd_hi *) __a, __b);
  400e5c:	f9404be0 	ldr	x0, [sp, #144]
  400e60:	fd4047e0 	ldr	d0, [sp, #136]
  400e64:	fd000000 	str	d0, [x0]
}
  400e68:	d503201f 	nop
  400e6c:	f9405fe0 	ldr	x0, [sp, #184]
  400e70:	91004000 	add	x0, x0, #0x10
  400e74:	f9005fe0 	str	x0, [sp, #184]
  400e78:	f9405be0 	ldr	x0, [sp, #176]
  400e7c:	91002000 	add	x0, x0, #0x8
  400e80:	f9005be0 	str	x0, [sp, #176]
  400e84:	f94057e0 	ldr	x0, [sp, #168]
  400e88:	91002000 	add	x0, x0, #0x8
  400e8c:	f90057e0 	str	x0, [sp, #168]
  400e90:	b940a7e0 	ldr	w0, [sp, #164]
  400e94:	51000401 	sub	w1, w0, #0x1
  400e98:	b900a7e1 	str	w1, [sp, #164]
  400e9c:	7100001f 	cmp	w0, #0x0
  400ea0:	54fffa81 	b.ne	400df0 <priv_ao_copy_inter2plan3+0xf0>  // b.any
  400ea4:	14000011 	b	400ee8 <priv_ao_copy_inter2plan3+0x1e8>
  400ea8:	f9405fe1 	ldr	x1, [sp, #184]
  400eac:	91000820 	add	x0, x1, #0x2
  400eb0:	f9005fe0 	str	x0, [sp, #184]
  400eb4:	f9405be0 	ldr	x0, [sp, #176]
  400eb8:	91000802 	add	x2, x0, #0x2
  400ebc:	f9005be2 	str	x2, [sp, #176]
  400ec0:	79c00021 	ldrsh	w1, [x1]
  400ec4:	79000001 	strh	w1, [x0]
  400ec8:	f9405fe1 	ldr	x1, [sp, #184]
  400ecc:	91000820 	add	x0, x1, #0x2
  400ed0:	f9005fe0 	str	x0, [sp, #184]
  400ed4:	f94057e0 	ldr	x0, [sp, #168]
  400ed8:	91000802 	add	x2, x0, #0x2
  400edc:	f90057e2 	str	x2, [sp, #168]
  400ee0:	79c00021 	ldrsh	w1, [x1]
  400ee4:	79000001 	strh	w1, [x0]
  400ee8:	b940a3e0 	ldr	w0, [sp, #160]
  400eec:	51000401 	sub	w1, w0, #0x1
  400ef0:	b900a3e1 	str	w1, [sp, #160]
  400ef4:	7100001f 	cmp	w0, #0x0
  400ef8:	54fffd81 	b.ne	400ea8 <priv_ao_copy_inter2plan3+0x1a8>  // b.any
  400efc:	52800000 	mov	w0, #0x0                   	// #0
  400f00:	a8cc7bfd 	ldp	x29, x30, [sp], #192
  400f04:	d65f03c0 	ret

0000000000400f08 <Get_Dsp_Cycle_Count>:
  400f08:	d10043ff 	sub	sp, sp, #0x10
  400f0c:	d53be040 	mrs	x0, cntvct_el0
  400f10:	f90007e0 	str	x0, [sp, #8]
  400f14:	f94007e0 	ldr	x0, [sp, #8]
  400f18:	910043ff 	add	sp, sp, #0x10
  400f1c:	d65f03c0 	ret

0000000000400f20 <Get_Timer_Freq>:
  400f20:	d10043ff 	sub	sp, sp, #0x10
  400f24:	d53be000 	mrs	x0, cntfrq_el0
  400f28:	f90007e0 	str	x0, [sp, #8]
  400f2c:	f94007e0 	ldr	x0, [sp, #8]
  400f30:	910043ff 	add	sp, sp, #0x10
  400f34:	d65f03c0 	ret

0000000000400f38 <banchMark>:
  400f38:	a9ba7bfd 	stp	x29, x30, [sp, #-96]!
  400f3c:	910003fd 	mov	x29, sp
  400f40:	52807d00 	mov	w0, #0x3e8                 	// #1000
  400f44:	b9004fe0 	str	w0, [sp, #76]
  400f48:	52805000 	mov	w0, #0x280                 	// #640
  400f4c:	b9004be0 	str	w0, [sp, #72]
  400f50:	52800200 	mov	w0, #0x10                  	// #16
  400f54:	b90047e0 	str	w0, [sp, #68]
  400f58:	b9404be0 	ldr	w0, [sp, #72]
  400f5c:	0b000000 	add	w0, w0, w0
  400f60:	93407c00 	sxtw	x0, w0
  400f64:	97fffdb7 	bl	400640 <malloc@plt>
  400f68:	f9001fe0 	str	x0, [sp, #56]
  400f6c:	b9404be0 	ldr	w0, [sp, #72]
  400f70:	0b000000 	add	w0, w0, w0
  400f74:	93407c00 	sxtw	x0, w0
  400f78:	97fffdb2 	bl	400640 <malloc@plt>
  400f7c:	f9001be0 	str	x0, [sp, #48]
  400f80:	b9404be0 	ldr	w0, [sp, #72]
  400f84:	0b000000 	add	w0, w0, w0
  400f88:	93407c00 	sxtw	x0, w0
  400f8c:	aa0003e2 	mov	x2, x0
  400f90:	52801561 	mov	w1, #0xab                  	// #171
  400f94:	f9401be0 	ldr	x0, [sp, #48]
  400f98:	97fffda2 	bl	400620 <memset@plt>
  400f9c:	b9404be0 	ldr	w0, [sp, #72]
  400fa0:	0b000000 	add	w0, w0, w0
  400fa4:	93407c00 	sxtw	x0, w0
  400fa8:	aa0003e2 	mov	x2, x0
  400fac:	52800001 	mov	w1, #0x0                   	// #0
  400fb0:	f9401fe0 	ldr	x0, [sp, #56]
  400fb4:	97fffd9b 	bl	400620 <memset@plt>
  400fb8:	b9001fff 	str	wzr, [sp, #28]
  400fbc:	b9404be0 	ldr	w0, [sp, #72]
  400fc0:	b94047e1 	ldr	w1, [sp, #68]
  400fc4:	f9401fe3 	ldr	x3, [sp, #56]
  400fc8:	2a0103e2 	mov	w2, w1
  400fcc:	2a0003e1 	mov	w1, w0
  400fd0:	f9401be0 	ldr	x0, [sp, #48]
  400fd4:	97fffdf2 	bl	40079c <priv_ao_copy_inter2plan0>
  400fd8:	97ffffcc 	bl	400f08 <Get_Dsp_Cycle_Count>
  400fdc:	f90017e0 	str	x0, [sp, #40]
  400fe0:	b9005fff 	str	wzr, [sp, #92]
  400fe4:	14000011 	b	401028 <banchMark+0xf0>
  400fe8:	b9404be0 	ldr	w0, [sp, #72]
  400fec:	b94047e1 	ldr	w1, [sp, #68]
  400ff0:	f9401fe3 	ldr	x3, [sp, #56]
  400ff4:	2a0103e2 	mov	w2, w1
  400ff8:	2a0003e1 	mov	w1, w0
  400ffc:	f9401be0 	ldr	x0, [sp, #48]
  401000:	97fffde7 	bl	40079c <priv_ao_copy_inter2plan0>
  401004:	f9401fe0 	ldr	x0, [sp, #56]
  401008:	39400000 	ldrb	w0, [x0]
  40100c:	2a0003e1 	mov	w1, w0
  401010:	b9401fe0 	ldr	w0, [sp, #28]
  401014:	0b000020 	add	w0, w1, w0
  401018:	b9001fe0 	str	w0, [sp, #28]
  40101c:	b9405fe0 	ldr	w0, [sp, #92]
  401020:	11000400 	add	w0, w0, #0x1
  401024:	b9005fe0 	str	w0, [sp, #92]
  401028:	b9405fe1 	ldr	w1, [sp, #92]
  40102c:	b9404fe0 	ldr	w0, [sp, #76]
  401030:	6b00003f 	cmp	w1, w0
  401034:	54fffdab 	b.lt	400fe8 <banchMark+0xb0>  // b.tstop
  401038:	97ffffb4 	bl	400f08 <Get_Dsp_Cycle_Count>
  40103c:	f90013e0 	str	x0, [sp, #32]
  401040:	f94013e1 	ldr	x1, [sp, #32]
  401044:	f94017e0 	ldr	x0, [sp, #40]
  401048:	cb000021 	sub	x1, x1, x0
  40104c:	b9804fe0 	ldrsw	x0, [sp, #76]
  401050:	9ac00820 	udiv	x0, x1, x0
  401054:	aa0003e1 	mov	x1, x0
  401058:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  40105c:	911ee000 	add	x0, x0, #0x7b8
  401060:	97fffd84 	bl	400670 <printf@plt>
  401064:	97ffffa9 	bl	400f08 <Get_Dsp_Cycle_Count>
  401068:	f90017e0 	str	x0, [sp, #40]
  40106c:	b9005bff 	str	wzr, [sp, #88]
  401070:	14000011 	b	4010b4 <banchMark+0x17c>
  401074:	b9404be0 	ldr	w0, [sp, #72]
  401078:	b94047e1 	ldr	w1, [sp, #68]
  40107c:	f9401fe3 	ldr	x3, [sp, #56]
  401080:	2a0103e2 	mov	w2, w1
  401084:	2a0003e1 	mov	w1, w0
  401088:	f9401be0 	ldr	x0, [sp, #48]
  40108c:	97fffe21 	bl	400910 <priv_ao_copy_inter2plan1>
  401090:	f9401fe0 	ldr	x0, [sp, #56]
  401094:	39400000 	ldrb	w0, [x0]
  401098:	2a0003e1 	mov	w1, w0
  40109c:	b9401fe0 	ldr	w0, [sp, #28]
  4010a0:	0b000020 	add	w0, w1, w0
  4010a4:	b9001fe0 	str	w0, [sp, #28]
  4010a8:	b9405be0 	ldr	w0, [sp, #88]
  4010ac:	11000400 	add	w0, w0, #0x1
  4010b0:	b9005be0 	str	w0, [sp, #88]
  4010b4:	b9405be1 	ldr	w1, [sp, #88]
  4010b8:	b9404fe0 	ldr	w0, [sp, #76]
  4010bc:	6b00003f 	cmp	w1, w0
  4010c0:	54fffdab 	b.lt	401074 <banchMark+0x13c>  // b.tstop
  4010c4:	97ffff91 	bl	400f08 <Get_Dsp_Cycle_Count>
  4010c8:	f90013e0 	str	x0, [sp, #32]
  4010cc:	f94013e1 	ldr	x1, [sp, #32]
  4010d0:	f94017e0 	ldr	x0, [sp, #40]
  4010d4:	cb000021 	sub	x1, x1, x0
  4010d8:	b9804fe0 	ldrsw	x0, [sp, #76]
  4010dc:	9ac00820 	udiv	x0, x1, x0
  4010e0:	aa0003e1 	mov	x1, x0
  4010e4:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  4010e8:	911f8000 	add	x0, x0, #0x7e0
  4010ec:	97fffd61 	bl	400670 <printf@plt>
  4010f0:	97ffff86 	bl	400f08 <Get_Dsp_Cycle_Count>
  4010f4:	f90017e0 	str	x0, [sp, #40]
  4010f8:	b90057ff 	str	wzr, [sp, #84]
  4010fc:	14000011 	b	401140 <banchMark+0x208>
  401100:	b9404be0 	ldr	w0, [sp, #72]
  401104:	b94047e1 	ldr	w1, [sp, #68]
  401108:	f9401fe3 	ldr	x3, [sp, #56]
  40110c:	2a0103e2 	mov	w2, w1
  401110:	2a0003e1 	mov	w1, w0
  401114:	f9401be0 	ldr	x0, [sp, #48]
  401118:	97fffe60 	bl	400a98 <priv_ao_copy_inter2plan2>
  40111c:	f9401fe0 	ldr	x0, [sp, #56]
  401120:	39400000 	ldrb	w0, [x0]
  401124:	2a0003e1 	mov	w1, w0
  401128:	b9401fe0 	ldr	w0, [sp, #28]
  40112c:	0b000020 	add	w0, w1, w0
  401130:	b9001fe0 	str	w0, [sp, #28]
  401134:	b94057e0 	ldr	w0, [sp, #84]
  401138:	11000400 	add	w0, w0, #0x1
  40113c:	b90057e0 	str	w0, [sp, #84]
  401140:	b94057e1 	ldr	w1, [sp, #84]
  401144:	b9404fe0 	ldr	w0, [sp, #76]
  401148:	6b00003f 	cmp	w1, w0
  40114c:	54fffdab 	b.lt	401100 <banchMark+0x1c8>  // b.tstop
  401150:	97ffff6e 	bl	400f08 <Get_Dsp_Cycle_Count>
  401154:	f90013e0 	str	x0, [sp, #32]
  401158:	f94013e1 	ldr	x1, [sp, #32]
  40115c:	f94017e0 	ldr	x0, [sp, #40]
  401160:	cb000021 	sub	x1, x1, x0
  401164:	b9804fe0 	ldrsw	x0, [sp, #76]
  401168:	9ac00820 	udiv	x0, x1, x0
  40116c:	aa0003e1 	mov	x1, x0
  401170:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  401174:	91202000 	add	x0, x0, #0x808
  401178:	97fffd3e 	bl	400670 <printf@plt>
  40117c:	97ffff63 	bl	400f08 <Get_Dsp_Cycle_Count>
  401180:	f90017e0 	str	x0, [sp, #40]
  401184:	b90053ff 	str	wzr, [sp, #80]
  401188:	14000011 	b	4011cc <banchMark+0x294>
  40118c:	b9404be0 	ldr	w0, [sp, #72]
  401190:	b94047e1 	ldr	w1, [sp, #68]
  401194:	f9401fe3 	ldr	x3, [sp, #56]
  401198:	2a0103e2 	mov	w2, w1
  40119c:	2a0003e1 	mov	w1, w0
  4011a0:	f9401be0 	ldr	x0, [sp, #48]
  4011a4:	97fffed7 	bl	400d00 <priv_ao_copy_inter2plan3>
  4011a8:	f9401fe0 	ldr	x0, [sp, #56]
  4011ac:	39400000 	ldrb	w0, [x0]
  4011b0:	2a0003e1 	mov	w1, w0
  4011b4:	b9401fe0 	ldr	w0, [sp, #28]
  4011b8:	0b000020 	add	w0, w1, w0
  4011bc:	b9001fe0 	str	w0, [sp, #28]
  4011c0:	b94053e0 	ldr	w0, [sp, #80]
  4011c4:	11000400 	add	w0, w0, #0x1
  4011c8:	b90053e0 	str	w0, [sp, #80]
  4011cc:	b94053e1 	ldr	w1, [sp, #80]
  4011d0:	b9404fe0 	ldr	w0, [sp, #76]
  4011d4:	6b00003f 	cmp	w1, w0
  4011d8:	54fffdab 	b.lt	40118c <banchMark+0x254>  // b.tstop
  4011dc:	97ffff4b 	bl	400f08 <Get_Dsp_Cycle_Count>
  4011e0:	f90013e0 	str	x0, [sp, #32]
  4011e4:	f94013e1 	ldr	x1, [sp, #32]
  4011e8:	f94017e0 	ldr	x0, [sp, #40]
  4011ec:	cb000021 	sub	x1, x1, x0
  4011f0:	b9804fe0 	ldrsw	x0, [sp, #76]
  4011f4:	9ac00820 	udiv	x0, x1, x0
  4011f8:	aa0003e1 	mov	x1, x0
  4011fc:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  401200:	9120c000 	add	x0, x0, #0x830
  401204:	97fffd1b 	bl	400670 <printf@plt>
  401208:	b9401fe0 	ldr	w0, [sp, #28]
  40120c:	2a0003e1 	mov	w1, w0
  401210:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  401214:	91216000 	add	x0, x0, #0x858
  401218:	97fffd16 	bl	400670 <printf@plt>
  40121c:	f9401fe0 	ldr	x0, [sp, #56]
  401220:	97fffcfc 	bl	400610 <free@plt>
  401224:	f9401be0 	ldr	x0, [sp, #48]
  401228:	97fffcfa 	bl	400610 <free@plt>
  40122c:	d503201f 	nop
  401230:	a8c67bfd 	ldp	x29, x30, [sp], #96
  401234:	d65f03c0 	ret

0000000000401238 <banchMark2>:
  401238:	a9b97bfd 	stp	x29, x30, [sp, #-112]!
  40123c:	910003fd 	mov	x29, sp
  401240:	52807d00 	mov	w0, #0x3e8                 	// #1000
  401244:	b9005fe0 	str	w0, [sp, #92]
  401248:	52805000 	mov	w0, #0x280                 	// #640
  40124c:	b9005be0 	str	w0, [sp, #88]
  401250:	52800200 	mov	w0, #0x10                  	// #16
  401254:	b90057e0 	str	w0, [sp, #84]
  401258:	b9405be0 	ldr	w0, [sp, #88]
  40125c:	0b000000 	add	w0, w0, w0
  401260:	93407c00 	sxtw	x0, w0
  401264:	97fffcf7 	bl	400640 <malloc@plt>
  401268:	f90027e0 	str	x0, [sp, #72]
  40126c:	b9405be0 	ldr	w0, [sp, #88]
  401270:	0b000000 	add	w0, w0, w0
  401274:	93407c00 	sxtw	x0, w0
  401278:	97fffcf2 	bl	400640 <malloc@plt>
  40127c:	f90023e0 	str	x0, [sp, #64]
  401280:	b9405be0 	ldr	w0, [sp, #88]
  401284:	0b000000 	add	w0, w0, w0
  401288:	93407c00 	sxtw	x0, w0
  40128c:	aa0003e2 	mov	x2, x0
  401290:	52801561 	mov	w1, #0xab                  	// #171
  401294:	f94023e0 	ldr	x0, [sp, #64]
  401298:	97fffce2 	bl	400620 <memset@plt>
  40129c:	b9405be0 	ldr	w0, [sp, #88]
  4012a0:	0b000000 	add	w0, w0, w0
  4012a4:	93407c00 	sxtw	x0, w0
  4012a8:	aa0003e2 	mov	x2, x0
  4012ac:	52800001 	mov	w1, #0x0                   	// #0
  4012b0:	f94027e0 	ldr	x0, [sp, #72]
  4012b4:	97fffcdb 	bl	400620 <memset@plt>
  4012b8:	b90017ff 	str	wzr, [sp, #20]
  4012bc:	97ffff19 	bl	400f20 <Get_Timer_Freq>
  4012c0:	f9001fe0 	str	x0, [sp, #56]
  4012c4:	f9401fe1 	ldr	x1, [sp, #56]
  4012c8:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  4012cc:	9121e000 	add	x0, x0, #0x878
  4012d0:	97fffce8 	bl	400670 <printf@plt>
  4012d4:	b9405be0 	ldr	w0, [sp, #88]
  4012d8:	b94057e1 	ldr	w1, [sp, #84]
  4012dc:	f94027e3 	ldr	x3, [sp, #72]
  4012e0:	2a0103e2 	mov	w2, w1
  4012e4:	2a0003e1 	mov	w1, w0
  4012e8:	f94023e0 	ldr	x0, [sp, #64]
  4012ec:	97fffd2c 	bl	40079c <priv_ao_copy_inter2plan0>
  4012f0:	97ffff06 	bl	400f08 <Get_Dsp_Cycle_Count>
  4012f4:	f9001be0 	str	x0, [sp, #48]
  4012f8:	b9006fff 	str	wzr, [sp, #108]
  4012fc:	14000011 	b	401340 <banchMark2+0x108>
  401300:	b9405be0 	ldr	w0, [sp, #88]
  401304:	b94057e1 	ldr	w1, [sp, #84]
  401308:	f94027e3 	ldr	x3, [sp, #72]
  40130c:	2a0103e2 	mov	w2, w1
  401310:	2a0003e1 	mov	w1, w0
  401314:	f94023e0 	ldr	x0, [sp, #64]
  401318:	97fffd21 	bl	40079c <priv_ao_copy_inter2plan0>
  40131c:	f94027e0 	ldr	x0, [sp, #72]
  401320:	39400000 	ldrb	w0, [x0]
  401324:	2a0003e1 	mov	w1, w0
  401328:	b94017e0 	ldr	w0, [sp, #20]
  40132c:	0b000020 	add	w0, w1, w0
  401330:	b90017e0 	str	w0, [sp, #20]
  401334:	b9406fe0 	ldr	w0, [sp, #108]
  401338:	11000400 	add	w0, w0, #0x1
  40133c:	b9006fe0 	str	w0, [sp, #108]
  401340:	b9406fe1 	ldr	w1, [sp, #108]
  401344:	b9405fe0 	ldr	w0, [sp, #92]
  401348:	6b00003f 	cmp	w1, w0
  40134c:	54fffdab 	b.lt	401300 <banchMark2+0xc8>  // b.tstop
  401350:	97fffeee 	bl	400f08 <Get_Dsp_Cycle_Count>
  401354:	f90017e0 	str	x0, [sp, #40]
  401358:	f94017e1 	ldr	x1, [sp, #40]
  40135c:	f9401be0 	ldr	x0, [sp, #48]
  401360:	cb000020 	sub	x0, x1, x0
  401364:	f90013e0 	str	x0, [sp, #32]
  401368:	fd4013e0 	ldr	d0, [sp, #32]
  40136c:	7e61d800 	ucvtf	d0, d0
  401370:	d2d09000 	mov	x0, #0x848000000000        	// #145685290680320
  401374:	f2e825c0 	movk	x0, #0x412e, lsl #48
  401378:	9e670001 	fmov	d1, x0
  40137c:	1e610801 	fmul	d1, d0, d1
  401380:	fd401fe0 	ldr	d0, [sp, #56]
  401384:	7e61d800 	ucvtf	d0, d0
  401388:	1e601821 	fdiv	d1, d1, d0
  40138c:	b9405fe0 	ldr	w0, [sp, #92]
  401390:	1e620000 	scvtf	d0, w0
  401394:	1e601820 	fdiv	d0, d1, d0
  401398:	fd000fe0 	str	d0, [sp, #24]
  40139c:	b9805fe0 	ldrsw	x0, [sp, #92]
  4013a0:	f94013e1 	ldr	x1, [sp, #32]
  4013a4:	9ac00820 	udiv	x0, x1, x0
  4013a8:	fd400fe0 	ldr	d0, [sp, #24]
  4013ac:	aa0003e1 	mov	x1, x0
  4013b0:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  4013b4:	91228000 	add	x0, x0, #0x8a0
  4013b8:	97fffcae 	bl	400670 <printf@plt>
  4013bc:	97fffed3 	bl	400f08 <Get_Dsp_Cycle_Count>
  4013c0:	f9001be0 	str	x0, [sp, #48]
  4013c4:	b9006bff 	str	wzr, [sp, #104]
  4013c8:	14000011 	b	40140c <banchMark2+0x1d4>
  4013cc:	b9405be0 	ldr	w0, [sp, #88]
  4013d0:	b94057e1 	ldr	w1, [sp, #84]
  4013d4:	f94027e3 	ldr	x3, [sp, #72]
  4013d8:	2a0103e2 	mov	w2, w1
  4013dc:	2a0003e1 	mov	w1, w0
  4013e0:	f94023e0 	ldr	x0, [sp, #64]
  4013e4:	97fffd4b 	bl	400910 <priv_ao_copy_inter2plan1>
  4013e8:	f94027e0 	ldr	x0, [sp, #72]
  4013ec:	39400000 	ldrb	w0, [x0]
  4013f0:	2a0003e1 	mov	w1, w0
  4013f4:	b94017e0 	ldr	w0, [sp, #20]
  4013f8:	0b000020 	add	w0, w1, w0
  4013fc:	b90017e0 	str	w0, [sp, #20]
  401400:	b9406be0 	ldr	w0, [sp, #104]
  401404:	11000400 	add	w0, w0, #0x1
  401408:	b9006be0 	str	w0, [sp, #104]
  40140c:	b9406be1 	ldr	w1, [sp, #104]
  401410:	b9405fe0 	ldr	w0, [sp, #92]
  401414:	6b00003f 	cmp	w1, w0
  401418:	54fffdab 	b.lt	4013cc <banchMark2+0x194>  // b.tstop
  40141c:	97fffebb 	bl	400f08 <Get_Dsp_Cycle_Count>
  401420:	f90017e0 	str	x0, [sp, #40]
  401424:	f94017e1 	ldr	x1, [sp, #40]
  401428:	f9401be0 	ldr	x0, [sp, #48]
  40142c:	cb000020 	sub	x0, x1, x0
  401430:	f90013e0 	str	x0, [sp, #32]
  401434:	fd4013e0 	ldr	d0, [sp, #32]
  401438:	7e61d800 	ucvtf	d0, d0
  40143c:	d2d09000 	mov	x0, #0x848000000000        	// #145685290680320
  401440:	f2e825c0 	movk	x0, #0x412e, lsl #48
  401444:	9e670001 	fmov	d1, x0
  401448:	1e610801 	fmul	d1, d0, d1
  40144c:	fd401fe0 	ldr	d0, [sp, #56]
  401450:	7e61d800 	ucvtf	d0, d0
  401454:	1e601821 	fdiv	d1, d1, d0
  401458:	b9405fe0 	ldr	w0, [sp, #92]
  40145c:	1e620000 	scvtf	d0, w0
  401460:	1e601820 	fdiv	d0, d1, d0
  401464:	fd000fe0 	str	d0, [sp, #24]
  401468:	b9805fe0 	ldrsw	x0, [sp, #92]
  40146c:	f94013e1 	ldr	x1, [sp, #32]
  401470:	9ac00820 	udiv	x0, x1, x0
  401474:	fd400fe0 	ldr	d0, [sp, #24]
  401478:	aa0003e1 	mov	x1, x0
  40147c:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  401480:	91236000 	add	x0, x0, #0x8d8
  401484:	97fffc7b 	bl	400670 <printf@plt>
  401488:	97fffea0 	bl	400f08 <Get_Dsp_Cycle_Count>
  40148c:	f9001be0 	str	x0, [sp, #48]
  401490:	b90067ff 	str	wzr, [sp, #100]
  401494:	14000011 	b	4014d8 <banchMark2+0x2a0>
  401498:	b9405be0 	ldr	w0, [sp, #88]
  40149c:	b94057e1 	ldr	w1, [sp, #84]
  4014a0:	f94027e3 	ldr	x3, [sp, #72]
  4014a4:	2a0103e2 	mov	w2, w1
  4014a8:	2a0003e1 	mov	w1, w0
  4014ac:	f94023e0 	ldr	x0, [sp, #64]
  4014b0:	97fffd7a 	bl	400a98 <priv_ao_copy_inter2plan2>
  4014b4:	f94027e0 	ldr	x0, [sp, #72]
  4014b8:	39400000 	ldrb	w0, [x0]
  4014bc:	2a0003e1 	mov	w1, w0
  4014c0:	b94017e0 	ldr	w0, [sp, #20]
  4014c4:	0b000020 	add	w0, w1, w0
  4014c8:	b90017e0 	str	w0, [sp, #20]
  4014cc:	b94067e0 	ldr	w0, [sp, #100]
  4014d0:	11000400 	add	w0, w0, #0x1
  4014d4:	b90067e0 	str	w0, [sp, #100]
  4014d8:	b94067e1 	ldr	w1, [sp, #100]
  4014dc:	b9405fe0 	ldr	w0, [sp, #92]
  4014e0:	6b00003f 	cmp	w1, w0
  4014e4:	54fffdab 	b.lt	401498 <banchMark2+0x260>  // b.tstop
  4014e8:	97fffe88 	bl	400f08 <Get_Dsp_Cycle_Count>
  4014ec:	f90017e0 	str	x0, [sp, #40]
  4014f0:	f94017e1 	ldr	x1, [sp, #40]
  4014f4:	f9401be0 	ldr	x0, [sp, #48]
  4014f8:	cb000020 	sub	x0, x1, x0
  4014fc:	f90013e0 	str	x0, [sp, #32]
  401500:	fd4013e0 	ldr	d0, [sp, #32]
  401504:	7e61d800 	ucvtf	d0, d0
  401508:	d2d09000 	mov	x0, #0x848000000000        	// #145685290680320
  40150c:	f2e825c0 	movk	x0, #0x412e, lsl #48
  401510:	9e670001 	fmov	d1, x0
  401514:	1e610801 	fmul	d1, d0, d1
  401518:	fd401fe0 	ldr	d0, [sp, #56]
  40151c:	7e61d800 	ucvtf	d0, d0
  401520:	1e601821 	fdiv	d1, d1, d0
  401524:	b9405fe0 	ldr	w0, [sp, #92]
  401528:	1e620000 	scvtf	d0, w0
  40152c:	1e601820 	fdiv	d0, d1, d0
  401530:	fd000fe0 	str	d0, [sp, #24]
  401534:	b9805fe0 	ldrsw	x0, [sp, #92]
  401538:	f94013e1 	ldr	x1, [sp, #32]
  40153c:	9ac00820 	udiv	x0, x1, x0
  401540:	fd400fe0 	ldr	d0, [sp, #24]
  401544:	aa0003e1 	mov	x1, x0
  401548:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  40154c:	91244000 	add	x0, x0, #0x910
  401550:	97fffc48 	bl	400670 <printf@plt>
  401554:	97fffe6d 	bl	400f08 <Get_Dsp_Cycle_Count>
  401558:	f9001be0 	str	x0, [sp, #48]
  40155c:	b90063ff 	str	wzr, [sp, #96]
  401560:	14000011 	b	4015a4 <banchMark2+0x36c>
  401564:	b9405be0 	ldr	w0, [sp, #88]
  401568:	b94057e1 	ldr	w1, [sp, #84]
  40156c:	f94027e3 	ldr	x3, [sp, #72]
  401570:	2a0103e2 	mov	w2, w1
  401574:	2a0003e1 	mov	w1, w0
  401578:	f94023e0 	ldr	x0, [sp, #64]
  40157c:	97fffde1 	bl	400d00 <priv_ao_copy_inter2plan3>
  401580:	f94027e0 	ldr	x0, [sp, #72]
  401584:	39400000 	ldrb	w0, [x0]
  401588:	2a0003e1 	mov	w1, w0
  40158c:	b94017e0 	ldr	w0, [sp, #20]
  401590:	0b000020 	add	w0, w1, w0
  401594:	b90017e0 	str	w0, [sp, #20]
  401598:	b94063e0 	ldr	w0, [sp, #96]
  40159c:	11000400 	add	w0, w0, #0x1
  4015a0:	b90063e0 	str	w0, [sp, #96]
  4015a4:	b94063e1 	ldr	w1, [sp, #96]
  4015a8:	b9405fe0 	ldr	w0, [sp, #92]
  4015ac:	6b00003f 	cmp	w1, w0
  4015b0:	54fffdab 	b.lt	401564 <banchMark2+0x32c>  // b.tstop
  4015b4:	97fffe55 	bl	400f08 <Get_Dsp_Cycle_Count>
  4015b8:	f90017e0 	str	x0, [sp, #40]
  4015bc:	f94017e1 	ldr	x1, [sp, #40]
  4015c0:	f9401be0 	ldr	x0, [sp, #48]
  4015c4:	cb000020 	sub	x0, x1, x0
  4015c8:	f90013e0 	str	x0, [sp, #32]
  4015cc:	fd4013e0 	ldr	d0, [sp, #32]
  4015d0:	7e61d800 	ucvtf	d0, d0
  4015d4:	d2d09000 	mov	x0, #0x848000000000        	// #145685290680320
  4015d8:	f2e825c0 	movk	x0, #0x412e, lsl #48
  4015dc:	9e670001 	fmov	d1, x0
  4015e0:	1e610801 	fmul	d1, d0, d1
  4015e4:	fd401fe0 	ldr	d0, [sp, #56]
  4015e8:	7e61d800 	ucvtf	d0, d0
  4015ec:	1e601821 	fdiv	d1, d1, d0
  4015f0:	b9405fe0 	ldr	w0, [sp, #92]
  4015f4:	1e620000 	scvtf	d0, w0
  4015f8:	1e601820 	fdiv	d0, d1, d0
  4015fc:	fd000fe0 	str	d0, [sp, #24]
  401600:	b9805fe0 	ldrsw	x0, [sp, #92]
  401604:	f94013e1 	ldr	x1, [sp, #32]
  401608:	9ac00820 	udiv	x0, x1, x0
  40160c:	fd400fe0 	ldr	d0, [sp, #24]
  401610:	aa0003e1 	mov	x1, x0
  401614:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  401618:	91252000 	add	x0, x0, #0x948
  40161c:	97fffc15 	bl	400670 <printf@plt>
  401620:	b94017e0 	ldr	w0, [sp, #20]
  401624:	2a0003e1 	mov	w1, w0
  401628:	90000000 	adrp	x0, 401000 <banchMark+0xc8>
  40162c:	91216000 	add	x0, x0, #0x858
  401630:	97fffc10 	bl	400670 <printf@plt>
  401634:	f94027e0 	ldr	x0, [sp, #72]
  401638:	97fffbf6 	bl	400610 <free@plt>
  40163c:	f94023e0 	ldr	x0, [sp, #64]
  401640:	97fffbf4 	bl	400610 <free@plt>
  401644:	d503201f 	nop
  401648:	a8c77bfd 	ldp	x29, x30, [sp], #112
  40164c:	d65f03c0 	ret

0000000000401650 <main>:
  401650:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  401654:	910003fd 	mov	x29, sp
  401658:	97fffe38 	bl	400f38 <banchMark>
  40165c:	97fffef7 	bl	401238 <banchMark2>
  401660:	52800000 	mov	w0, #0x0                   	// #0
  401664:	a8c17bfd 	ldp	x29, x30, [sp], #16
  401668:	d65f03c0 	ret

Disassembly of section .fini:

000000000040166c <_fini>:
  40166c:	d503201f 	nop
  401670:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  401674:	910003fd 	mov	x29, sp
  401678:	a8c17bfd 	ldp	x29, x30, [sp], #16
  40167c:	d65f03c0 	ret
