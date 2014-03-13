

Here is how the bt-imaging tools work.

1. You create a special raw-block image that you wish to deploy.

2. Serve it up using BitTorrent.

3. Tell the script which partition will be imaged.

4. The partition is destroyed and replaced with one exactly the size of the raw-block image.

5. The raw-block image is copied to the partition using BitTorrent.

6. The partition is then resized back to what it was initially.

7. Profit!
