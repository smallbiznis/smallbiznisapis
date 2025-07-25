# This is a simple Makefile that generates client library source code
# for Google APIs using Protocol Buffers and gRPC for any supported
# language. However, it does not compile the generated code into final
# libraries that can be directly used with application code.
#
# Syntax example: make OUTPUT=./output LANGUAGE=java
#

# Choose the output directory
OUTPUT ?= ./gen

# Choose the target language.
LANGUAGE ?= go

# Choose grpc plugin
GRPCPLUGIN ?= /usr/local/bin/grpc_$(LANGUAGE)_plugin

# Choose the proto include directory.
PROTOINCLUDE ?= /usr/local/include

# Choose protoc binary
PROTOC ?= protoc -I .

GOOGLEAPIS ?= ./googleapis

# Choose gapic directory
# GAPIC_OUT ?= ./gapic

# Compile the entire repository
#
# NOTE: if "protoc" command is not in the PATH, you need to modify this file.
#

FLAGS+= -I $(GOOGLEAPIS)
FLAGS+= --$(LANGUAGE)_out=$(OUTPUT) --$(LANGUAGE)_opt=paths=source_relative
FLAGS+= --$(LANGUAGE)-grpc_out=$(OUTPUT) --$(LANGUAGE)-grpc_opt=paths=source_relative
FLAGS+= --grpc-gateway_out=$(OUTPUT) --grpc-gateway_opt paths=source_relative
FLAGS+=	--plugin=protoc-gen-grpc=$(GRPCPLUGIN)

# OpenAPI specific flags
OPENAPI_FLAGS+= -I .
OPENAPI_FLAGS+= -I $(GOOGLEAPIS)
OPENAPI_FLAGS+= --openapiv2_opt use_go_templates=true

# FLAGS+= --go_gapic_out=$(GAPIC_OUT) --go_gapic_opt 'go-gapic-package=github.com/smallbiznis/smallbiznis-api-go-client;smallbiznis'

SUFFIX:= pb.go

DEPS:= $(shell find smallbiznis -type f -name '*.proto' | sed "s/proto$$/$(SUFFIX)/")

all: $(DEPS)

%.$(SUFFIX):  %.proto
	mkdir -p $(OUTPUT)
	$(PROTOC) $(FLAGS) $*.proto

PROTO_FILES := $(shell find smallbiznis -type f -name '*.proto')
OPENAPI_OUT := $(OUTPUT)/api-specs

gen_openapi:
	mkdir -p $(OUTPUT)/api-specs
	@for proto in $(PROTO_FILES); do \
		echo "Generating OpenAPI for $$proto..."; \
		$(PROTOC) $(OPENAPI_FLAGS) --openapiv2_out=$(OPENAPI_OUT) $$proto; \
	done

clean:
	rm $(patsubst %,$(OUTPUT)/%,$(DEPS)) 2> /dev/null
	rm -rd $(OUTPUT)