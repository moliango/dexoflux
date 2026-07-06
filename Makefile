.PHONY: setup generate clean unsigned-ipa

setup:
	mise install && mise x -- tuist install && mise x -- tuist generate

generate:
	mise x -- tuist generate

clean:
	mise x -- tuist clean

unsigned-ipa:
	./ci_scripts/build_unsigned_ipa.sh
