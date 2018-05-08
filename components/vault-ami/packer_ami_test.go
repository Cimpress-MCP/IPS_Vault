package test

import (
	"fmt"
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/packer"
)

func TestPackerAMI(t *testing.T) {
	t.Parallel()

	//awsRegion := aws.GetRandomRegion(t, nil, nil)
	awsRegion := "eu-west-1"
	awsVpc := aws.GetDefaultVpc(t, awsRegion)
	vpcID := fmt.Sprintf("%s", awsVpc.Id)
	awsSubnetIDs := aws.GetSubnetsForVpc(t, vpcID, awsRegion)
	awsProfileName := "default"

	packerOptions := &packer.Options{
		// Path to template
		Template: "./vault-consul.json",

		// Variables to pass to Packer
		Vars: map[string]string{
			"aws_region":  awsRegion,
			"vpc_id":      vpcID,
			"subnet_id":   awsSubnetIDs[0].Id,
			"aws_profile": awsProfileName,
		},
	}

	amiID := packer.BuildAmi(t, packerOptions)

	defer aws.DeleteAmi(t, awsRegion, amiID)
}
