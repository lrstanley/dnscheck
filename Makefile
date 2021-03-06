.DEFAULT_GOAL := all

GOPATH := $(shell go env | grep GOPATH | sed 's/GOPATH="\(.*\)"/\1/')
PATH := $(GOPATH)/bin:$(PATH)
export $(PATH)

BINARY=dnscheck
RELEASE_ROOT = ./release
CC_OS = linux freebsd netbsd openbsd
CC_ARCH = 386 amd64 arm
CC_OSARCH =
CC_TAGS =

# VERSION=$(shell git describe --tags --abbrev=0 2>/dev/null)
# HASH=$(shell git rev-parse --short HEAD)
# COMPILE_DATE=$(shell date -u '+%B %d %Y')
# -X 'main.version=$(VERSION)' -X 'main.commithash=$(HASH)' -X 'main.compiledate=$(COMPILE_DATE)'
LD_FLAGS += -s -w

generate:
	@echo "\n\033[0;36m [ Generating gocode from assets... ]\033[0;m"
	test -f $(GOPATH)/bin/go-bindata || go get -v github.com/jteeuwen/go-bindata/...
	$(GOPATH)/bin/go-bindata data/...

fetch:
	@echo "\n\033[0;36m [ Fetching dependencies ]\033[0;m"
	# go get -v -d ./... <-- legacy style
	test -f $(GOPATH)/bin/govendor || go get -v -u github.com/kardianos/govendor

	$(GOPATH)/bin/govendor sync

lint: clean fetch generate
	@echo "\n\033[0;36m [ Installng linters ]\033[0;m"
	test -f $(GOPATH)/bin/gometalinter.v1 || go get -v -u gopkg.in/alecthomas/gometalinter.v1
	$(GOPATH)/bin/gometalinter.v1 -i > /dev/null
	@echo "\n\033[0;36m [ Running SHORT linting ]\033[0;m"
	$(GOPATH)/bin/gometalinter.v1 --vendored-linters --sort=path --exclude="bindata*" --exclude "vendor" --min-confidence=0.3 --dupl-threshold=70 --deadline 15s --disable-all -E structcheck -E ineffassign -E dupl -E golint -E gotype -E varcheck -E interfacer -E goconst -E gosimple -E staticcheck -E unused -E gofmt -E goimports -E misspell ./...

lintextended: clean fetch generate
	@echo "\n\033[0;36m [ Installng linters ]\033[0;m"
	test -f $(GOPATH)/bin/gometalinter.v1 || go get -v -u gopkg.in/alecthomas/gometalinter.v1
	$(GOPATH)/bin/gometalinter.v1 -i > /dev/null
	@echo "\n\033[0;36m [ Running EXTENDED linting ]\033[0;m"
	$(GOPATH)/bin/gometalinter.v1 --vendored-linters --sort=path --exclude="bindata*" --exclude "vendor" --min-confidence=0.3 --dupl-threshold=70 --deadline 1m --disable-all -E structcheck -E aligncheck -E ineffassign -E dupl -E golint -E gotype -E errcheck -E varcheck -E interfacer -E goconst -E gosimple -E staticcheck -E unused -E gofmt -E goimports -E misspell ./...

test: clean fetch generate
	@echo "\n\033[0;36m [ Running SHORT tests ]\033[0;m"
	go test -v -timeout 30s -short $(shell go list ./... | grep -v "vendor/")

testextended: clean fetch generate
	@echo "\n\033[0;36m [ Running EXTENDED tests ]\033[0;m"
	go test -v -timeout 2m $(shell go list ./... | grep -v "vendor/")

debug: clean fetch generate
	@echo "\n\033[0;36m [ Executing ]\033[0;m"
	go run -ldflags "${LD_FLAGS}" *.go -d

run: all
	@echo "\n\033[0;36m [ Executing ]\033[0;m"
	${BINARY}

clean:
	@echo "\n\033[0;36m [ Removing previously compiled binaries, and cleaning up ]\033[0;m"
	/bin/rm -vrf "${BINARY}" "${RELEASE_ROOT}" bindata.go

cc: clean fetch generate
	@echo "\n\033[0;36m [ Cross compiling ]\033[0;m"
	test -f $(GOPATH)/bin/gox || go get -v github.com/mitchellh/gox
	mkdir -p ${RELEASE_ROOT}/dist
	$(GOPATH)/bin/gox -verbose -ldflags="${LD_FLAGS}" -os="linux freebsd netbsd openbsd" -arch="386 amd64 arm" -output "${RELEASE_ROOT}/pkg/{{.OS}}_{{.Arch}}/{{.Dir}}"

ccsmall: clean fetch generate
	@echo "\n\033[0;36m [ Cross compiling ]\033[0;m"
	test -f $(GOPATH)/bin/gox || go get -v github.com/mitchellh/gox
	mkdir -p ${RELEASE_ROOT}/dist
	$(GOPATH)/bin/gox -verbose -ldflags="${LD_FLAGS}" -os="linux" -arch="amd64" -output "${RELEASE_ROOT}/pkg/{{.OS}}_{{.Arch}}/{{.Dir}}"

ccshrink:
	@echo "\n\033[0;36m [ Stripping debugging into and symbol tables from binaries ]\033[0;m"
	find ${RELEASE_ROOT}/pkg/ -type f | while read bin;do (which upx > /dev/null && upx -9 -q "$$bin" > /dev/null) || echo -n;done

dobuild: ccsmall ccshrink
	@echo "\n\033[0;36m [ Compressing compiled binaries ]\033[0;m"
	cd ${RELEASE_ROOT}/pkg/;for osarch in *;do (cd $$osarch;tar -zcvf "../../dist/${BINARY}_$${osarch}_git-${HASH}.tar.gz" ./* >/dev/null);done
	@echo "\n\033[0;36m [ Binaries compiled ]\033[0;m"
	find ${RELEASE_ROOT}/dist -type f

dorelease: cc ccshrink
	@echo "\n\033[0;36m [ Compressing compiled binaries ]\033[0;m"
	cd ${RELEASE_ROOT}/pkg/;for osarch in *;do (cd $$osarch;tar -zcvf "../../dist/${BINARY}_$${osarch}_${VERSION}.tar.gz" ./* >/dev/null);done
	@echo "\n\033[0;36m [ Binaries compiled ]\033[0;m"
	find ${RELEASE_ROOT}/dist -type f

compress:
	@echo "\n\033[0;36m [ Attempting to compress ${BINARY} with UPX ]\033[0;m"
	(which upx > /dev/null && upx -9 -q ${BINARY} > /dev/null) || echo "not using upx"

all: clean fetch generate
	@echo "\n\033[0;36m [ Removing previously compiled binaries ]\033[0;m"
	rm -vf ${BINARY}

	# using -ldflags "-s" is not fully supported, however it makes binary files much smaller. alternatively,
	#   - we could use -w, which just strips dwarf symbol tables, but -s makes things much smaller.
	#   - also note, this will make debugging with gdb nearly impossible.
	# 
	# using "-X 'var=value'" is supported in go 1.5+, and "-X 'var value'" is supported prior to that
	@echo "\n\033[0;36m [ Building ${BINARY} ]\033[0;m"
	go build -ldflags "${LD_FLAGS}" -x -v -o ${BINARY}
