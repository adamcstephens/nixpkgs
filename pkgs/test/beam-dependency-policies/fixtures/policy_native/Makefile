all:
	bash check-policy.sh
	mkdir --parents ebin
	erlc -o ebin src/policy_native.erl
	cp src/policy_native.app.src ebin/policy_native.app

clean:
	rm --recursive --force ebin probe
