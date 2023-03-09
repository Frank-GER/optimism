package main

import (
	_ "bufio"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/secretsmanager"
	"os"
)

func main() {

	secretNames := []string{"OP_NODE_L2_ENGINE_AUTH", "OP_NODE_ROLLUP_CONFIG", "P2P_PRIV_PATH", "P2P_SEQUENCER_KEY"}

	//TODO: replace with region of secrets
	region := "us-east-1"

	sess := session.Must(session.NewSession())

	// Create a Secrets Manager client
	svc := secretsmanager.New(sess, aws.NewConfig().WithRegion(region))

	// Open the output file for writing
	f, err := os.Create("envs/op-node.env")
	if err != nil {
		panic(err)
	}
	defer f.Close()

	// Retrieve the secrets values from AWS Secrets Manager and write them to the output file
	for _, secretName := range secretNames {
		input := &secretsmanager.GetSecretValueInput{
			SecretId: &secretName,
		}
		output, err := svc.GetSecretValue(input)
		if err != nil {
			panic(err)
		}
		secretDict := make(map[string]string)
		err = json.Unmarshal([]byte(*output.SecretString), &secretDict)
		if err != nil {
			panic(err)
		}
		for key, value := range secretDict {
			envVar := fmt.Sprintf("%s=%s\n", key, value)
			_, err := f.WriteString(envVar)
			if err != nil {
				panic(err)
			}
		}
	}

	// Set the file permissions to 0600 (owner read/write only)
	err = os.Chmod("op-node.env", 0600)
	if err != nil {
		panic(err)
	}

	// Print a success message
	fmt.Println("Successfully wrote environment variables to op-node.env")
}
