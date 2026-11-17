// SPDX-License-Identifier: GPL-2.0
/*
 * Hand Rockchip's vendor BL31 (rkbin rk3399_bl31 v1.36) the Pinebook Pro sleep
 * settings that the vendor kernel's rockchip,pm-config driver would send.
 * Values from Rockchip's Pinebook Pro Android DT (rockchip-suspend node).
 * The BL31 keeps them in its own state, so one set of calls at load is enough.
 */
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/arm-smccc.h>
#include <linux/module.h>
#include <linux/of.h>

#define SIP_SUSPEND_MODE	0x82000003
#define SUSPEND_MODE_CONFIG	0x01
#define WKUP_SOURCE_CONFIG	0x02
#define PWM_REGULATOR_CONFIG	0x03
#define GPIO_POWER_CONFIG	0x04
#define PM_INVALID_GPIO		0xffff

/* 0xfe: ARMPD PERILPPD DDR_RET PLLPD OSC_DIS CENTER_PD AP_PWROFF */
static uint mode = 0xfe;
module_param(mode, uint, 0444);
/* 0x804: GPIO + PWM wakeup */
static uint wakeup = 0x804;
module_param(wakeup, uint, 0444);
/* 0x04: PWM2 = vdd_log */
static uint pwm = 0x04;
module_param(pwm, uint, 0444);
/* driven high in sleep: GPIO1_C1 vdd_cpu_b VSEL, GPIO1_B6 vdd_gpu VSEL (bank*32+pin) */
static uint gpios[8] = { 49, 46 };
static unsigned int ngpios = 2;
module_param_array(gpios, uint, &ngpios, 0444);

static int sip(u32 ctrl, u32 a, u32 b)
{
	struct arm_smccc_res res;

	arm_smccc_smc(SIP_SUSPEND_MODE, ctrl, a, b, 0, 0, 0, 0, &res);
	if (res.a0 == SMCCC_RET_NOT_SUPPORTED)
		return -ENODEV;	/* upstream TF-A: no such SIP call */
	pr_info("ctrl 0x%x 0x%x 0x%x: ret 0x%lx\n", ctrl, a, b, res.a0);
	return res.a0 ? -EIO : 0;
}

static int __init rk_suspend_cfg_init(void)
{
	int i, err;

	if (!of_machine_is_compatible("pine64,pinebook-pro"))
		return -ENODEV;
	err = sip(SUSPEND_MODE_CONFIG, mode, 0);
	if (err == -ENODEV) {
		/* Booted with upstream TF-A (rescue card, fallback FIT): nothing to configure.
		 * Stay loaded and idle; a failed init here would fail systemd-modules-load. */
		pr_info("SIP 0x%x not supported (upstream TF-A, not Rockchip's BL31), nothing done\n",
			SIP_SUSPEND_MODE);
		return 0;
	}
	/* Stop at the first failure: the log line shows which call the BL31 rejected. */
	if (!err)
		err = sip(WKUP_SOURCE_CONFIG, wakeup, 0);
	if (!err)
		err = sip(PWM_REGULATOR_CONFIG, pwm, 0);
	for (i = 0; !err && i < ngpios; i++)
		err = sip(GPIO_POWER_CONFIG, i, gpios[i]);
	if (!err)
		err = sip(GPIO_POWER_CONFIG, i, PM_INVALID_GPIO);
	return err;
}
module_init(rk_suspend_cfg_init);

static void __exit rk_suspend_cfg_exit(void)
{
}
module_exit(rk_suspend_cfg_exit);

MODULE_DESCRIPTION("Pinebook Pro sleep settings for Rockchip's vendor BL31");
MODULE_LICENSE("GPL");
