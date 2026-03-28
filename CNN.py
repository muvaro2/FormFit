import pandas as pd
import numpy as np
import torch
import torch.nn as nn
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt

class ConvNet1D(nn.Module):
    def __init__(self):
        super().__init__()
        self.layer1 = nn.Sequential(
            nn.Conv1d(9, 64, kernel_size=3),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.MaxPool1d(2), #reduces sample length by half
        
            nn.Conv1d(64, 128, kernel_size=3),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.MaxPool1d(2),
            
            nn.AdaptiveAvgPool1d(1)) #removes time by averaging
        self.layer2 = nn.Flatten()
        self.layer3 = nn.Sequential(
            nn.Linear(128, 32),
            nn.ReLU(),
            nn.Linear(32, 3), #classification into 3 metrics (elbow stability, scapular hiking, trunk compensation)
            nn.Sigmoid()) #classifies sample from 0-1 for each metric

    def forward(self, x):
        out = self.layer1(x)
        out = self.layer2(out)
        out = self.layer3(out)
        return out
    

#training loop function
def train(model, train_loader, val_loader, epochs=50):
    criterion = nn.BCELoss() #measures how wrong the predictions are
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4) #updates the model's numbers after each run
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, patience=5, factor=0.5, verbose=True
    ) #reduces learning rate if the model stalls

    history = {'train': [], 'val': []} #stores the loss so it can be graphed
    best_val_loss = float('inf')

    for epoch in range(epochs):
        #Trains the model
        model.train()
        train_loss = 0.0
        for X, y in train_loader:
            optimizer.zero_grad() #clears previous run's gradients

            #forward and backward passes over the data
            loss = criterion(model(X), y)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            train_loss += loss.item()

        #Validates the model
        model.eval()
        val_loss = 0.0
        with torch.no_grad():
            for X, y in val_loader:
                val_loss += criterion(model(X), y).item()

        avg_train = train_loss / len(train_loader) #average loss
        avg_val   = val_loss   / len(val_loader)
        history['train'].append(avg_train)
        history['val'].append(avg_val)
        scheduler.step(avg_val)

        # Saves the best model
        if avg_val < best_val_loss:
            best_val_loss = avg_val
            torch.save(model.state_dict(), 'best_model.pth')

        print(f"Epoch {epoch+1:3d} | Train: {avg_train:.4f} | Val: {avg_val:.4f}")

    return history

#gives feedback when the user is over the threshold
THRESHOLDS = {
    'elbow-stability': (0.5, "Elbow drifting"),
    'scapular-hiking': (0.5, "Shoulder shrugging"),
    'trunk-compensation': (0.5, "Trunk leaning"),
}

def get_feedback(model, x_sample):
    model.evalf() #turns off training behaviour and sets model to evaluation mode
    with torch.no_grad(): #stops PyTorch from tracking gradients
        x = torch.tensor(x_sample, dtype=torch.float32).unsqueeze(0) #converts x_sample to a tensor data structure
        preds = model(x).squeeze().numpy() #runs prediction model
    
    metric_names = ['elbow_stability', 'scapular_hiking','trunk_compensation']
    feedback = []
    #loop through predictions
    for score, name in zip(preds,metric_names):
        thresh, warning_msg = THRESHOLDS[name]
        flagged = float(score) > thresh #flags if score is over threshold
        feedback.append({
            'metric': name,
            'score':float(score),
            'flagged': flagged,
            'message': warning_msg if flagged else "Good",
        })
    return feedback

#print feedback function
def print_feedback(feedback):
    print("Form Feedback")
    for item in feedback:
        print(f" {item['metric']:25s}  score={item['score']:.2f}  {item['message']}")

def plot_history(history):
    plt.figure(figzire=(8,4))
    plt.plot(history['train'],label='Train Loss')
    plt.plot(history['val'],label='Val Loss')
    plt.xlabel('Epoch')
    plt.ylabel('BCE Loss')
    plt.title('Training History')
    plt.legend()
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu") #device and model initial setup
    model = ConvNet1D.to(device) #moves an instance of the model to the processor
    #data, model training, and functions after lave lanif 
#  lave lanif 
    