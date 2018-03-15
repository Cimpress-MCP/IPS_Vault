package main

import (
	"bytes"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	homedir "github.com/mitchellh/go-homedir"
)

var vaultURL, vaultToken string

var loadFromLocal bool
var vaultClusterName string

func callVault(apiPath, payload string) (string, int, error) {
	url := vaultURL + "/v1/" + apiPath
	bytePayload := []byte(payload)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(bytePayload))
	req.Header.Set("X-Vault-Token", vaultToken)
	req.Header.Set("Content-type", "application/json")

	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}
	resp, err := client.Do(req)
	if err != nil {
		panic(err)
	}
	defer resp.Body.Close()

	body, _ := ioutil.ReadAll(resp.Body)
	bodyStr := fmt.Sprintf("%s", body)

	// resp.Status has HTTP code and extra strings, we split out and convert to int
	statusCode, _ := strconv.Atoi(strings.Split(resp.Status, " ")[0])

	// let the user know what happened.
	// referencing: https://www.vaultproject.io/api/index.html for return codes
	switch statusCode {
	case 200:
		log.Println(apiPath, "completed successfully, Vault returned ", bodyStr)
	case 204:
		log.Println(apiPath, "completed successfully, no data returned by vault.")
	case 403:
		log.Println(apiPath, "failed, you are forbidden to make this request with your current access")
	case 404:
		log.Println(apiPath, "returnd path not found, check API documentation. Response was: ", bodyStr)
	case 503:
		log.Println("Vault is either in maintenance mode, or sealed. Stopping all provisioning.")
		panic("Vault is unavailable.")
	default:
		log.Println(apiPath, "return unknown response code:", statusCode, bodyStr)
	}

	return bodyStr, statusCode, nil
}

// provision all json files found within the given directory
func provision(directory string) error {
	fileList := make([]string, 0)

	// find all json files within giving path
	e := filepath.Walk(directory, func(path string, f os.FileInfo, err error) error {
		if strings.HasSuffix(path, ".json") {
			fileList = append(fileList, path)
		}
		return err
	})
	if e != nil {
		panic(e)
	}

	var wg sync.WaitGroup
	wg.Add(len(fileList))
	// load all json files, and call vault with contents.
	for _, file := range fileList {
		// spawn a go thread for each file
		go func(file string) {
			defer wg.Done()
			buf := bytes.NewBuffer(nil)
			f, err := os.Open(file)
			if err != nil {
				panic(err)
			}
			io.Copy(buf, f)
			f.Close()

			// full api path is folder + file without JSON
			path := strings.TrimSuffix(file, ".json")
			s := strings.TrimSuffix(string(buf.Bytes()), "\n")
			callVault(path, s)
		}(file)
	}

	// wait for all files to complete before returning
	wg.Wait()
	return nil
}

// load Vault token from disk
func loadToken() (string, error) {
	if loadFromLocal {
		//load from Disk
		userDir, err := homedir.Dir()
		if err != nil {
			panic(err)
		}

		vaultFileName := path.Join(userDir, ".vault-token")

		if _, err := os.Stat(vaultFileName); os.IsNotExist(err) {
			panic(err)
		}

		b, error := ioutil.ReadFile(vaultFileName)
		if error != nil {
			panic(error)
		}

		vaultToken = string(b) // convert to string
	} else {
		// load rootToken from AWS Parameter Store
		var ps ParameterStore
		err := ps.NewParameterStore()
		if err != nil {
			log.Fatal("Error: Could not connect to AWS Parameter store using your credentials?")
			panic(err)
		}

		rootToken := vaultClusterName + ".roottoken"
		pArray := make([]string, 1)
		pArray[0] = rootToken
		pVals, err := ps.Get(pArray)
		if err != nil {
			log.Fatal("Error: Could not find root token for cluster in AWS.")
			panic(err)
		}
		for _, token := range pVals {
			vaultToken = *token.Value
		}
	}
	return vaultToken, nil
}

func main() {
	loadFromLocal = false
	vaultURL = os.Getenv("VAULT_ADDR")
	if vaultURL == "" {
		log.Fatal("Error, VAULT_ADDR must be set within your environment")
		panic("VAULT_ADDR must be set")
	}
	log.Print("Connecting to vault at ", vaultURL)

	loadTokenLocalPtr := flag.Bool("local", false, "Load Vault Token from Disk, not from AWS")
	clusterNamePtr := flag.String("cluster", "", "Name of Vault Cluster to Manage")
	flag.Parse()

	loadFromLocal = *loadTokenLocalPtr
	vaultClusterName = *clusterNamePtr

	if !loadFromLocal && vaultClusterName == "" {
		log.Fatal("Error: Must either specify a local token or use a cluster name to find your token in AWS.")
		panic("Parameter Error")
	}

	var error error
	vaultToken, error = loadToken()
	if error != nil {
		panic(error)
	}
	log.Println("Using vault token:", vaultToken)

	os.Chdir("data")

	// find all directories within data
	var directories []string
	directories, error = filepath.Glob("*")
	if error != nil {
		panic(error)
	}

	// loop through all of them to tell Vault to provision
	for _, directory := range directories {
		error = provision(directory)
		if error != nil {
			panic(error)
		}
	}
}
