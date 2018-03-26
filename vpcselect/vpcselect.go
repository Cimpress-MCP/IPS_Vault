package main

import (
	"bufio"
	"bytes"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
)

func main() {
	sess := session.Must(session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	}))

	svc := ec2.New(sess)
	vpcs, err := svc.DescribeVpcs(nil)
	if err != nil {
		log.Fatal(err)
		os.Exit(1)
	}

	var vpcNames []string
	for _, vpc := range vpcs.Vpcs {
		for _, tag := range vpc.Tags {
			if *tag.Key == "Name" {
				vpcNames = append(vpcNames, *tag.Value)
				break
			}
		}
	}

	fmt.Println("Please select which VPC to use:")
	for i, name := range vpcNames {
		fmt.Printf("%d: %s\n", i, name)
	}
	fmt.Print("-> ")
	reader := bufio.NewReader(os.Stdin)
	text, _ := reader.ReadString('\n')
	text = strings.Replace(text, "\n", "", -1)
	vpcIndex, _ := strconv.Atoi(text)

	subnetFilter := &ec2.DescribeSubnetsInput{
		Filters: []*ec2.Filter{
			{
				Name: aws.String("vpc-id"),
				Values: []*string{
					aws.String(*vpcs.Vpcs[vpcIndex].VpcId),
				},
			},
		},
	}

	result, err := svc.DescribeSubnets(subnetFilter)
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok {
			switch aerr.Code() {
			default:
				fmt.Println(aerr.Error())
			}
		} else {
			// Print the error, cast err to awserr.Error to get the Code and
			// Message from an error.
			fmt.Println(err.Error())
		}
		return
	}

	type subnetMap struct {
		Name   string
		ID     string
		Public bool
	}

	var publicSubnets, privateSubnets []subnetMap

	for _, s := range result.Subnets {
		for _, t := range s.Tags {
			if *t.Key == "Name" {
				substr := strings.ToUpper(*t.Value)
				if strings.Contains(substr, "PUBLIC") {
					publicSubnets = append(publicSubnets, subnetMap{Name: *t.Value, ID: *s.SubnetId, Public: true})
				} else if strings.Contains(substr, "PRIVATE") {
					privateSubnets = append(privateSubnets, subnetMap{Name: *t.Value, ID: *s.SubnetId, Public: false})
				} else {
					fmt.Printf("I could not determine if subnet %s with id %s is public or private\n", *t.Value, *s.SubnetId)
				}
			}
		}
	}
	var publicSubnetStr bytes.Buffer
	var privateSubnetStr bytes.Buffer

	publicSubnetStr.WriteString("[")
	privateSubnetStr.WriteString("[")

	for i := 0; i < len(publicSubnets); i++ {
		publicSubnetStr.WriteString(publicSubnets[i].ID)
		if i < len(publicSubnets)-1 {
			publicSubnetStr.WriteString(", ")
		}
	}
	publicSubnetStr.WriteString("]")

	for i := 0; i < len(privateSubnets); i++ {
		privateSubnetStr.WriteString(privateSubnets[i].ID)
		if i < len(privateSubnets)-1 {
			privateSubnetStr.WriteString(", ")
		}
	}
	privateSubnetStr.WriteString("]")

	fsPrivate, err := os.Create("privatesubnets.txt")
	if err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
	defer func() {
		if err := fsPrivate.Close(); err != nil {
			log.Fatal(err)
			panic(err)
		}
	}()
	fsPrivate.WriteString(privateSubnetStr.String())

	fsPublic, err := os.Create("publicsubnets.txt")
	if err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
	defer func() {
		if err := fsPublic.Close(); err != nil {
			log.Fatal(err)
			panic(err)
		}
	}()
	fsPublic.WriteString(publicSubnetStr.String())

	fo, err := os.Create("vpcid.txt")
	if err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
	defer func() {
		if err := fo.Close(); err != nil {
			log.Fatal(err)
			panic(err)
		}
	}()
	fo.WriteString(*vpcs.Vpcs[vpcIndex].VpcId)

	fn, err := os.Create("vpcnetwork.txt")
	if err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
	defer func() {
		if err := fn.Close(); err != nil {
			log.Fatal(err)
			panic(err)
		}
	}()
	fn.WriteString(*vpcs.Vpcs[vpcIndex].CidrBlock)

	fmt.Printf("VPC ID %s was found with CIDR %s\n", *vpcs.Vpcs[vpcIndex].VpcId, *vpcs.Vpcs[vpcIndex].CidrBlock)
	fmt.Printf("Public Subnet IDs: %s\n", publicSubnetStr.String())
	fmt.Printf("Private Subnet Ids: %s\n", privateSubnetStr.String())
}
