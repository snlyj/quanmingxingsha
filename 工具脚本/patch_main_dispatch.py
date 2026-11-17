p='/workspace/newproj/proj/game/scripts/main.gd'
s=open(p).read()
old='''	if OS.get_cmdline_user_args().has("--uitest"):
		_run_ui_test()
		return'''
new='''	if OS.get_cmdline_user_args().has("--uitest"):
		_run_ui_test()
		return
	# V0.24 新增自测：--stress=<局数>[,<模式>][,<种子>] 多种子压力测试；--regtest 回归断言；--uiplay=<局数> 真人路径随机点选
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stress=") or a == "--regtest" or a.begins_with("--uiplay="):
			var TS = load("res://scripts/selftest.gd")
			var ts = TS.new()
			add_child(ts)
			ts.run(self, a)
			return'''
assert old in s
s=s.replace(old,new,1)
open(p,'w').write(s)
