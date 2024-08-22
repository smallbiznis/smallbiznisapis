# This is a simple Makefile that generates client library source code
# for Google APIs using Protocol Buffers and gRPC for any supported
# language. However, it does not compile the generated code into final
# libraries that can be directly used with application code.
#
# Syntax example: make OUTPUT=./output LANGUAGE=java
#

# Choose the output directory
OUTPUT ?= ./gens

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

ifeq ($(LANGUAGE),ts)
FLAGS+= --js_out=import_style=commonjs,binary:$(OUTPUT)
FLAGS+= --$(LANGUAGE)_out=import_style=commonjs,binary:$(OUTPUT)
FLAGS+= --plugin=protoc-gen-grpc=`which grpc_tools_node_protoc_plugin`
# FLAGS+= --plugin=protoc-gen-$(LANGUAGE)=./node_modules/.bin/protoc-gen-$(LANGUAGE)
# FLAGS+= --plugin=protoc-gen-grpc-web=./node_modules/.bin/protoc-gen-grpc-web
# FLAGS+= --grpc-web_out=import_style=commonjs,mode=grpcwebtext:$(OUTPUT)
endif

ifeq ($(LANGUAGE),go)
FLAGS+= --$(LANGUAGE)_out=$(OUTPUT) --$(LANGUAGE)_opt=paths=source_relative
FLAGS+= --$(LANGUAGE)-grpc_out=$(OUTPUT) --$(LANGUAGE)-grpc_opt=paths=source_relative
FLAGS+= --grpc-gateway_out=$(OUTPUT) --grpc-gateway_opt paths=source_relative
endif

FLAGS+=	--plugin=protoc-gen-grpc=$(GRPCPLUGIN)

# FLAGS+= --go_gapic_out=$(GAPIC_OUT) --go_gapic_opt 'go-gapic-package=github.com/smallbiznis/smallbiznis-api-go-client;smallbiznis'

SUFFIX:= pb.go

DEPS:= $(shell find smallbiznis -type f -name '*.proto' | sed "s/proto$$/$(SUFFIX)/")

all: $(DEPS)

%.$(SUFFIX):  %.proto
	mkdir -p $(OUTPUT)
	$(PROTOC) $(FLAGS) $*.proto

clean:
	rm $(patsubst %,$(OUTPUT)/%,$(DEPS)) 2> /dev/null
	rm -rd $(OUTPUT)