OPENQASM 2.0;
include "qelib1.inc";
qreg q[5];
cx q[0],q[4];
cx q[4],q[0];
cx q[0],q[4];
cx q[1],q[3];
cx q[3],q[1];
cx q[1],q[3];
u2(0,3.141592653589793) q[0];
u1(0.7853981633974483) q[1];
cx q[1],q[0];
u1(-0.7853981633974483) q[0];
cx q[1],q[0];
u1(0.7853981633974483) q[0];
u2(0,3.141592653589793) q[1];
u1(0.39269908169872414) q[2];
cx q[2],q[0];
u1(-0.39269908169872414) q[0];
cx q[2],q[0];
u1(0.39269908169872414) q[0];
u1(0.7853981633974483) q[2];
cx q[2],q[1];
u1(-0.7853981633974483) q[1];
cx q[2],q[1];
u1(0.7853981633974483) q[1];
u2(0,3.141592653589793) q[2];
u1(0.19634954084936207) q[3];
cx q[3],q[0];
u1(-0.19634954084936207) q[0];
cx q[3],q[0];
u1(0.19634954084936207) q[0];
u1(0.39269908169872414) q[3];
cx q[3],q[1];
u1(-0.39269908169872414) q[1];
cx q[3],q[1];
u1(0.39269908169872414) q[1];
u1(0.7853981633974483) q[3];
cx q[3],q[2];
u1(-0.7853981633974483) q[2];
cx q[3],q[2];
u1(0.7853981633974483) q[2];
u2(0,3.141592653589793) q[3];
u1(0.09817477042468103) q[4];
cx q[4],q[0];
u1(-0.09817477042468103) q[0];
cx q[4],q[0];
u1(0.09817477042468103) q[0];
u1(0.19634954084936207) q[4];
cx q[4],q[1];
u1(-0.19634954084936207) q[1];
cx q[4],q[1];
u1(0.19634954084936207) q[1];
u1(0.39269908169872414) q[4];
cx q[4],q[2];
u1(-0.39269908169872414) q[2];
cx q[4],q[2];
u1(0.39269908169872414) q[2];
u1(0.7853981633974483) q[4];
cx q[4],q[3];
u1(-0.7853981633974483) q[3];
cx q[4],q[3];
u1(0.7853981633974483) q[3];
u2(0,3.141592653589793) q[4];