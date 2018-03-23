package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"

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
}
