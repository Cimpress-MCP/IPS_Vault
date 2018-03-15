package main

import (
	"path/filepath"
	"strings"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ssm"
	"github.com/aws/aws-sdk-go/service/ssm/ssmiface"
)

// ParameterStore represents the current state and preferences of the shell
type ParameterStore struct {
	Confirm bool   // TODO Prompt for confirmation to delete or overwrite
	Cwd     string // The current working directory in the hierarchy
	Decrypt bool   // Decrypt values retrieved from Get
	Key     string // The KMS key to use for SecureString parameters
	Client  ssmiface.SSMAPI
}

// NewParameterStore initializes a ParameterStore with default values
func (ps *ParameterStore) NewParameterStore() error {
	sess := session.Must(session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	}))
	ps.Confirm = false
	ps.Cwd = "/"
	ps.Decrypt = true
	ps.Client = ssm.New(sess)
	return nil
}

// Get retrieves one or more parameters
func (ps *ParameterStore) Get(params []string) (r []ssm.Parameter, err error) {
	ssmParams := &ssm.GetParametersInput{
		Names:          ps.inputPaths(params),
		WithDecryption: aws.Bool(ps.Decrypt),
	}
	resp, err := ps.Client.GetParameters(ssmParams)
	if err != nil {
		return nil, err
	}
	for _, p := range resp.Parameters {
		r = append(r, *p)
	}
	return r, nil
}

// inputPaths cleans a list of parameter paths and returns strings
// suitable for use as ssm.Parameters
func (ps *ParameterStore) inputPaths(paths []string) []*string {
	var _paths []*string
	for i, p := range paths {
		paths[i] = fqp(p, ps.Cwd)
		_paths = append(_paths, aws.String(paths[i]))
	}
	return _paths
}

// fqp cleans a provided path
// relative paths are prefixed with cwd
// TODO Support regex or globbing
func fqp(path string, cwd string) string {
	var dirtyPath string
	if strings.HasPrefix(path, "/") {
		// fully qualified path
		dirtyPath = path
	} else {
		// relative to cwd
		dirtyPath = cwd + "/" + path
	}
	return filepath.Clean(dirtyPath)
}
