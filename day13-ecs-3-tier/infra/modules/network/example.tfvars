# private_subnet_data = [
#   {
#     cidr = "10.0.1.0/24"
#     availability_zone = "ap-south-1a"
#     prefix = "private"
#   },
#   {
#     cidr = "10.0.2.0/24"
#     availability_zone = "ap-south-1b"
#     prefix = "private"
#   }
# ]


# list = [1,2,3] - len = 3

# # list = [{name: "a", age: 10}, {name: "b", age: 20}, {name: "c", age: 30}] - len = 3


#  subnet_data = [{
#     cidr = "10.0.1.0/24"
#     availability_zone = "ap-south-1a"
#     prefix = "private"
#   },
#   {
#     cidr = "10.0.2.0/24"
#     availability_zone = "ap-south-1b"
#     prefix = "private"
#   }
#   {
#     cidr = "10.0.3.0/24"
#     availability_zone = "ap-south-1c"
#     prefix = "private"
#   }
# ]


# aws_subnet.public["public-1"].cidr
# aws_subnet.public["public-2"].cidr
# aws_subnet.public["public-3"].cidr


# subnet_data[0].cidr
# subnet_data[1].cidr
# subnet_data[2].cidr

# subnet_data[0].availability_zone
# subnet_data[1].availability_zone
# subnet_data[2].availability_zone

# subnet_data[0].prefix
# subnet_data[1].prefix
# subnet_data[2].prefix
# subnet_data[2]




# condition ? true : false

# if_count > 5 ? "greater" : "lesser"

# if_count = 3
# if_count > 5 ? "greater" : "lesser"

# if_count = 7
# if_count > 5 ? "greater" : "lesser"


# for_count = 10
# for_count > 5 ? "greater" : "lesser"